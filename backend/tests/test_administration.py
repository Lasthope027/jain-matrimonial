from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from uuid import UUID, uuid4
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import insert, select, update
from app import administration, profiles, models as m
from app.main import app
from app.create_admin import create_administrator
from test_auth import database, register, headers


@pytest.fixture
def context(database,monkeypatch):
    engine, settings, client = database
    monkeypatch.setattr(administration,'get_engine',lambda:engine)
    monkeypatch.setattr(profiles,'get_engine',lambda:engine)
    a,_ = register(client,'parent@example.test')
    create_administrator('admin@example.test','long-test-password')
    admin=client.post('/api/v1/auth/admin/login',json={'email':'admin@example.test','password':'long-test-password'}).json()
    return engine,client,headers(a),headers(admin),a


def profile(client,admin,name='Asha Jain',**changes):
    body={'full_name':name,'gender':'FEMALE','date_of_birth':'1996-05-12','current_location':'Pune','community':'Shwetambar'}
    body.update(changes)
    result=client.post('/api/v1/admin/profiles',headers=admin,json=body)
    assert result.status_code == 201,result.text
    return result.json()


def test_dashboard_counts_actual_profiles_and_responses(context):
    engine,client,_,admin,_=context
    a=profile(client,admin,'One',status='APPROVED')
    b=profile(client,admin,'Two',status='APPROVED')
    profile(client,admin,'Three',account_email='parent@example.test')
    p=profile(client,admin,'Four')
    client.put(f"/api/v1/admin/profiles/{p['id']}/verification",headers=admin,json={'version':1,'status':'REJECTED','note':'Incomplete'})
    admin_id=UUID(client.get('/api/v1/auth/me',headers=admin).json()['id'])
    with engine.begin() as c:
        pending=c.execute(insert(m.proposals).values(profile_a_id=min(UUID(a['id']),UUID(b['id'])),
            profile_b_id=max(UUID(a['id']),UUID(b['id'])),created_by=admin_id).returning(m.proposals.c.id)).scalar_one()
        c.execute(insert(m.responses).values(proposal_id=pending,profile_id=UUID(a['id']),responded_by=admin_id,response='ACCEPTED'))
    result=client.get('/api/v1/admin/dashboard',headers=admin)
    assert result.status_code == 200,result.text
    stats=result.json()
    assert stats['total_profiles']==4 and stats['approved_profiles']==2
    assert stats['pending_verification']==1 and stats['rejected_profiles']==1
    assert stats['active_proposals']==1 and stats['pending_responses']==1
    assert stats['total_customers']==1 and stats['unassociated_profiles']==3
    with engine.begin() as c:
        c.execute(update(m.proposals).values(status='MUTUALLY_ACCEPTED'))
    stats=client.get('/api/v1/admin/dashboard',headers=admin).json()
    assert stats['active_proposals']==1 and stats['mutually_accepted_proposals']==1 and stats['pending_responses']==0


def test_new_registration_visible_without_restart(context):
    _,client,_,admin,_=context
    assert client.get('/api/v1/admin/dashboard',headers=admin).json()['total_customers']==1
    register(client,'new@example.test')
    assert client.get('/api/v1/admin/dashboard',headers=admin).json()['total_customers']==2
    rows=client.get('/api/v1/admin/customers?q=NEW%40EXAMPLE.TEST',headers=admin).json()
    assert rows['total']==1 and rows['items'][0]['email_verified_at']


def test_create_customer_requires_otp_and_hides_credentials(context):
    engine,client,_,admin,_=context
    response=client.post('/api/v1/admin/customers',headers=admin,json={'email':' Office@Example.Test '})
    assert response.status_code==201,response.text
    created=response.json()
    assert created['email']=='office@example.test' and created['email_verified_at'] is None and created['active']
    assert 'password_hash' not in created and 'access_token' not in created
    assert client.post('/api/v1/admin/customers',headers=admin,json={'email':'office@example.test'}).status_code==409
    session,_=register(client,'office@example.test')
    detail=client.get(f"/api/v1/admin/customers/{created['id']}",headers=admin).json()
    assert detail['email_verified_at'] and detail['version']==2
    assert client.get('/api/v1/auth/me',headers=headers(session)).json()['id']==created['id']
    with engine.connect() as c:
        assert len(c.execute(select(m.users).where(m.users.c.email=='office@example.test')).all())==1


def test_deactivation_revokes_all_sessions_without_changing_profiles(context):
    _,client,_,admin,session=context
    me=client.get('/api/v1/auth/me',headers=headers(session)).json()
    p=profile(client,admin,account_email=me['email'],status='APPROVED')
    customer=client.get(f"/api/v1/admin/customers/{me['id']}",headers=admin).json()
    result=client.put(f"/api/v1/admin/customers/{me['id']}/activation",headers=admin,json={'version':customer['version'],'active':False})
    assert result.status_code==200 and result.json()['active'] is False
    assert result.json()['profiles'][0]['status']=='APPROVED'
    assert client.get('/api/v1/auth/me',headers=headers(session)).status_code==401
    assert client.post('/api/v1/auth/refresh',json={'refresh_token':session['refresh_token']}).status_code==401
    assert client.put(f"/api/v1/admin/customers/{me['id']}/activation",headers=admin,json={'version':customer['version'],'active':True}).status_code==409
    reactivated=client.put(f"/api/v1/admin/customers/{me['id']}/activation",headers=admin,json={'version':result.json()['version'],'active':True})
    assert reactivated.status_code==200
    assert client.get('/api/v1/auth/me',headers=headers(session)).status_code==401
    assert client.post('/api/v1/auth/refresh',json={'refresh_token':session['refresh_token']}).status_code==401


@pytest.mark.parametrize('route',['/dashboard','/customers','/audit-logs'])
def test_all_administration_reads_are_role_protected(context,route):
    _,client,customer,_,_=context
    assert client.get('/api/v1/admin'+route).status_code==401
    assert client.get('/api/v1/admin'+route,headers=customer).status_code==403


def test_customer_management_cannot_mutate_roles_or_administrators(context):
    _,client,customer,admin,_=context
    admin_id=client.get('/api/v1/auth/me',headers=admin).json()['id']
    assert client.get(f'/api/v1/admin/customers/{admin_id}',headers=admin).status_code==404
    assert client.put(f'/api/v1/admin/customers/{admin_id}/activation',headers=admin,json={'version':1,'active':False}).status_code==404
    assert client.post('/api/v1/admin/customers',headers=customer,json={'email':'x@example.test'}).status_code==403
    assert client.post('/api/v1/admin/customers',headers=admin,json={'email':'x@example.test','role':'ADMINISTRATOR'}).status_code==422
    assert client.post('/api/v1/admin/customers',headers=admin,json={'email':'admin@example.test'}).status_code==409


def test_customer_list_pagination_profile_counts_and_activation_filters(context):
    _,client,_,admin,_=context
    profile(client,admin,account_email='parent@example.test')
    new=client.post('/api/v1/admin/customers',headers=admin,json={'email':'other@example.test'}).json()
    client.put(f"/api/v1/admin/customers/{new['id']}/activation",headers=admin,json={'version':1,'active':False})
    rows=client.get('/api/v1/admin/customers?active=true',headers=admin).json()
    assert rows['total']==1 and rows['items'][0]['profile_count']==1
    rows=client.get('/api/v1/admin/customers?limit=1',headers=admin).json()
    assert len(rows['items'])==1 and rows['total']==2 and rows['next_offset']==1
    second=client.get('/api/v1/admin/customers?limit=1&offset=1',headers=admin).json()
    assert second['items'][0]['id']!=rows['items'][0]['id'] and second['next_offset'] is None


def test_profile_search_combined_filters_uuid_literal_wildcards_and_age(context):
    _,client,_,admin,_=context
    year=date.today().year
    a=profile(client,admin,'Asha Jain',date_of_birth=f'{year-30}-01-01',status='APPROVED')
    profile(client,admin,'Other Person',gender='MALE',current_location='Mumbai',community='Digambar')
    result=client.get('/api/v1/admin/profiles',headers=admin,params={
        'q':'asha','gender':'FEMALE','age_min':29,'age_max':31,'location':'pUnE','community':'SHWET','status':'APPROVED'})
    assert result.status_code==200 and result.json()['total']==1
    assert client.get('/api/v1/admin/profiles',headers=admin,params={'q':a['id'][:8]}).json()['total']==1
    assert client.get('/api/v1/admin/profiles',headers=admin,params={'q':'%'}).json()['total']==0
    assert client.get('/api/v1/admin/profiles',headers=admin,params={'q':"' OR 1=1 --"}).json()['total']==0
    assert client.get('/api/v1/admin/profiles?age_min=40&age_max=20',headers=admin).status_code==422
    assert client.get('/api/v1/admin/profiles?gender=invalid',headers=admin).status_code==422
    assert client.get('/api/v1/admin/profiles?unassociated_only=true',headers=admin).json()['total']==2


def test_concurrent_creation_and_activation_have_one_winner(context):
    _,client,_,admin,session=context
    with ThreadPoolExecutor(max_workers=2) as pool:
        result=list(pool.map(lambda _:TestClient(app).post('/api/v1/admin/customers',headers=admin,json={'email':'race@example.test'}).status_code,range(2)))
    assert sorted(result)==[201,409]
    user_id=client.get('/api/v1/auth/me',headers=headers(session)).json()['id']
    row=client.get(f'/api/v1/admin/customers/{user_id}',headers=admin).json()
    with ThreadPoolExecutor(max_workers=2) as pool:
        result=list(pool.map(lambda _:TestClient(app).put(f'/api/v1/admin/customers/{user_id}/activation',headers=admin,json={'version':row['version'],'active':False}).status_code,range(2)))
    assert sorted(result)==[200,409]


def test_audit_records_include_actor_and_safe_customer_events(context):
    _,client,_,admin,_=context
    created=client.post('/api/v1/admin/customers',headers=admin,json={'email':'office@example.test'}).json()
    result=client.get('/api/v1/admin/audit-logs?q=customer_created',headers=admin)
    assert result.status_code==200 and result.json()['total']==1
    event=result.json()['items'][0]
    assert event['actor_email']=='admin@example.test' and event['entity_id']==created['id']
    assert 'password_hash' not in result.text and 'access_hash' not in result.text and 'code_hash' not in result.text
    assert client.get('/api/v1/admin/audit-logs?limit=101',headers=admin).status_code==422


def test_deactivation_invalidates_pending_codes_as_well_as_sessions(context):
    engine,client,_,admin,session=context
    me=client.get('/api/v1/auth/me',headers=headers(session)).json()
    with engine.begin() as c:
        from app.auth import now
        c.execute(update(m.otp).where(m.otp.c.email==me['email']).values(resend_after=now()-timedelta(seconds=1)))
    code=client.post('/api/v1/auth/otp/request',json={'email':me['email']}).json()['development_otp']
    row=client.get(f"/api/v1/admin/customers/{me['id']}",headers=admin).json()
    row=client.put(f"/api/v1/admin/customers/{me['id']}/activation",headers=admin,json={'version':row['version'],'active':False}).json()
    client.put(f"/api/v1/admin/customers/{me['id']}/activation",headers=admin,json={'version':row['version'],'active':True})
    assert client.post('/api/v1/auth/otp/verify',json={'email':me['email'],'code':code}).status_code==401


def test_activation_requires_explicit_boolean_and_integer_version(context):
    _,client,_,admin,session=context
    user_id=client.get('/api/v1/auth/me',headers=headers(session)).json()['id']
    path=f'/api/v1/admin/customers/{user_id}/activation'
    assert client.put(path,headers=admin,json={'version':1,'active':'false'}).status_code==422
    assert client.put(path,headers=admin,json={'version':True,'active':False}).status_code==422
    assert client.put(path,headers=admin,json={'version':1,'active':False,'role':'ADMINISTRATOR'}).status_code==422


def test_customer_search_treats_sql_patterns_as_literal_text(context):
    _,client,_,admin,_=context
    assert client.get('/api/v1/admin/customers',headers=admin,params={'q':'%'}).json()['total']==0
    assert client.get('/api/v1/admin/customers',headers=admin,params={'q':"' OR 1=1 --"}).json()['total']==0

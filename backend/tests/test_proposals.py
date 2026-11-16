from concurrent.futures import ThreadPoolExecutor
from uuid import UUID,uuid4
import io
import pytest
from PIL import Image
from sqlalchemy import select,update
from fastapi.testclient import TestClient
from app import proposals,notifications,profiles,documents,administration,models as m
from app.main import app
from app.create_admin import create_administrator
from test_auth import database,register,headers


@pytest.fixture
def context(database,monkeypatch,tmp_path):
    engine,settings,client=database;settings.storage_path=str(tmp_path)
    for module in (proposals,notifications,profiles,documents,administration):monkeypatch.setattr(module,'get_engine',lambda:engine)
    monkeypatch.setattr(documents,'get_settings',lambda:settings)
    sessions=[register(client,email)[0] for email in ('one@example.test','two@example.test','outsider@example.test')]
    create_administrator('admin@example.test','long-test-password')
    admin=client.post('/api/v1/auth/admin/login',json={'email':'admin@example.test','password':'long-test-password'}).json()
    a,b,out=[headers(s) for s in sessions];ah=headers(admin)
    def make(owner,name):
        row=client.post('/api/v1/profiles',headers=owner,json={'full_name':name,'gender':'FEMALE','date_of_birth':'1996-05-12',
            'current_location':'Pune','height_cm':165,'community':'Shwetambar','education':{'qualification':'M.Com','profession':'Accountant','company':'PRIVATE EMPLOYER','annual_income':'900000.00'},
            'family':{'father_name':'PRIVATE FATHER'}}).json()
        stream=io.BytesIO();Image.new('RGB',(10,10),'white').save(stream,'PNG')
        doc=client.post(f"/api/v1/profiles/{row['id']}/documents",headers={**owner,'Content-Type':'image/png'},
            params={'version':row['version'],'filename':name+'-private-biodata.png','kind':'BIODATA'},content=stream.getvalue()).json()['document']
        row=client.get(f"/api/v1/profiles/{row['id']}",headers=owner).json()
        row=client.put(f"/api/v1/admin/profiles/{row['id']}/verification",headers=ah,json={'version':row['version'],'status':'APPROVED'}).json()
        return row,doc
    pa,da=make(a,'Private One');pb,db=make(b,'Private Two')
    return engine,client,a,b,out,ah,pa,pb,da,db,tmp_path


def create(ctx):
    _,c,_,_,_,admin,a,b,*_=ctx
    response=c.post('/api/v1/admin/proposals',headers=admin,json={'profile_a_id':a['id'],'profile_b_id':b['id'],
        'profile_a_version':a['version'],'profile_b_version':b['version']})
    assert response.status_code==201,response.text
    return response.json()


def respond(ctx,p,side,choice='ACCEPTED'):
    _,c,a,b,_,_,pa,pb,*_=ctx
    return c.post(f"/api/v1/proposals/{p['id']}/responses",headers=a if side=='a' else b,
        json={'profile_id':pa['id'] if side=='a' else pb['id'],'response':choice})


def mutual(ctx):
    p=create(ctx)
    assert respond(ctx,p,'a').json()['status']=='PENDING'
    result=respond(ctx,p,'b');assert result.status_code==200,result.text
    assert result.json()['status']=='MUTUALLY_ACCEPTED'
    return result.json()


def authorise(ctx,p):
    _,c,_,_,_,admin,_,_,da,db,_=ctx
    result=c.post(f"/api/v1/admin/proposals/{p['id']}/sharing",headers=admin,
        json={'version':p['version'],'document_ids':[da['id'],db['id']]})
    assert result.status_code==200,result.text
    return result.json()


def test_customer_preview_is_explicitly_limited_and_outsiders_are_denied(context):
    _,c,a,b,out,admin,pa,pb,da,db,_=context
    p=create(context);detail=c.get(f"/api/v1/proposals/{p['id']}",headers=a)
    data=detail.json();assert detail.status_code==200
    assert set(data['match'])=={'age','height_cm','community','location','education','profession'}
    for secret in ('Private Two','PRIVATE EMPLOYER','PRIVATE FATHER','900000','1996-05-12',db['id'],db['original_name'],'two@example.test'):
        assert secret not in detail.text
    assert data['own_profile']['full_name']=='Private One' and data['shared_documents']==[]
    assert c.get('/api/v1/proposals',headers=out).json()['total']==0
    assert c.get(f"/api/v1/proposals/{p['id']}",headers=out).status_code==404
    assert c.get('/api/v1/admin/proposals',headers=a).status_code==403
    assert c.get(f"/api/v1/profiles/{pb['id']}",headers=a).status_code==404
    assert c.get(f"/api/v1/documents/{db['id']}/download",headers=a).status_code==404


def test_mutual_acceptance_still_requires_explicit_administrator_sharing(context):
    engine,c,a,b,_,admin,pa,pb,da,db,_=context
    p=create(context)
    endpoint=f"/api/v1/admin/proposals/{p['id']}/sharing"
    body={'version':p['version'],'document_ids':[da['id'],db['id']]}
    assert c.post(endpoint,headers=admin,json=body).status_code==409
    assert respond(context,p,'a').json()['status']=='PENDING'
    assert c.post(endpoint,headers=admin,json=body).status_code==409
    p=respond(context,p,'b').json()
    url=f"/api/v1/proposals/{p['id']}/documents/{db['id']}/download"
    assert c.get(url,headers=a).status_code==404
    assert c.get(f"/api/v1/proposals/{p['id']}",headers=a).json()['shared_documents']==[]
    assert c.post(endpoint,headers=a,json=body).status_code==403
    shared=authorise(context,p)
    assert c.get(url,headers=a).status_code==200
    assert c.get(f"/api/v1/proposals/{p['id']}/documents/{da['id']}/download",headers=b).status_code==200
    assert c.get(f"/api/v1/proposals/{p['id']}/documents/{da['id']}/download",headers=a).status_code==404
    assert c.get(f"/api/v1/documents/{db['id']}/download",headers=a).status_code==404
    with engine.connect() as connection:
        records=connection.execute(select(m.sharing)).mappings().all()
        assert len(records)==2 and all(r['authorised_by'] and r['document_sha256'] and r['recipient_account_id'] and not r['revoked_at'] for r in records)
    again=authorise(context,p) # Lost-response retry is idempotent, not duplicate release.
    assert len(again['sharing_records'])==2 and again['version']==shared['version']


def test_rejection_is_final_and_responses_cannot_be_forged_or_changed(context):
    _,c,a,b,out,_,pa,pb,*_=context;p=create(context)
    url=f"/api/v1/proposals/{p['id']}/responses"
    assert c.post(url,headers=a,json={'profile_id':pb['id'],'response':'ACCEPTED'}).status_code==403
    assert c.post(url,headers=out,json={'profile_id':pa['id'],'response':'ACCEPTED'}).status_code==404
    assert respond(context,p,'a','REJECTED').json()['status']=='REJECTED'
    assert respond(context,p,'a','REJECTED').status_code==200
    assert respond(context,p,'a','ACCEPTED').status_code==409
    assert respond(context,p,'b','ACCEPTED').status_code==409
    assert c.get('/api/v1/proposals?status=REJECTED',headers=a).json()['total']==1


def test_concurrent_independent_acceptance_and_immutable_same_party_choice(context):
    _,c,a,b,_,_,pa,pb,*_=context;p=create(context)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results=list(pool.map(lambda side:respond(context,p,side).status_code,['a','b']))
    assert results==[200,200]
    assert c.get(f"/api/v1/proposals/{p['id']}",headers=a).json()['status']=='MUTUALLY_ACCEPTED'
    assert respond(context,p,'a','REJECTED').status_code==409


@pytest.mark.parametrize('change',['edit','document','verification','association','deactivation'])
def test_consent_changes_cancel_and_revoke_shared_access(context,change):
    engine,c,a,b,out,admin,pa,pb,da,db,_=context
    p=authorise(context,mutual(context))
    if change=='edit':
        assert c.put(f"/api/v1/profiles/{pa['id']}",headers=a,json={'version':pa['version'],'full_name':'Changed private name','gender':'FEMALE','date_of_birth':'1996-05-12'}).status_code==200
    elif change=='document':
        assert c.delete(f"/api/v1/documents/{da['id']}?version={pa['version']}",headers=a).status_code==200
    elif change=='verification':
        assert c.put(f"/api/v1/admin/profiles/{pa['id']}/verification",headers=admin,json={'version':pa['version'],'status':'INACTIVE'}).status_code==200
    elif change=='association':
        assert c.put(f"/api/v1/admin/profiles/{pa['id']}/account",headers=admin,json={'version':pa['version'],'email':'outsider@example.test'}).status_code==200
        assert c.get('/api/v1/proposals',headers=out).json()['total']==0
    else:
        me=c.get('/api/v1/auth/me',headers=a).json()
        account=c.get(f"/api/v1/admin/customers/{me['id']}",headers=admin).json()
        assert c.put(f"/api/v1/admin/customers/{me['id']}/activation",headers=admin,json={'version':account['version'],'active':False}).status_code==200
    detail=c.get(f"/api/v1/proposals/{p['id']}",headers=b).json()
    assert detail['status']=='CANCELLED' and detail['shared_documents']==[]
    assert c.get(f"/api/v1/proposals/{p['id']}/documents/{da['id']}/download",headers=b).status_code==404
    with engine.connect() as connection:
        assert all(connection.execute(select(m.sharing.c.revoked_at)).scalars())


def test_cancelled_history_uses_snapshots_and_never_leaks_updated_private_fields(context):
    _,c,a,b,out,admin,pa,pb,*_=context;p=create(context)
    c.put(f"/api/v1/admin/profiles/{pa['id']}/account",headers=admin,json={'version':pa['version'],'email':'outsider@example.test'})
    pa=c.get(f"/api/v1/profiles/{pa['id']}",headers=admin).json()
    c.put(f"/api/v1/profiles/{pa['id']}",headers=out,json={'version':pa['version'],'full_name':'NEW OWNER PRIVATE NAME','gender':'FEMALE','date_of_birth':'1996-05-12'})
    response=c.get(f"/api/v1/proposals/{p['id']}",headers=a)
    assert response.status_code==200 and 'NEW OWNER PRIVATE NAME' not in response.text
    assert response.json()['own_profile']['full_name']=='Private One'


def test_creation_requires_current_approved_distinct_owners_and_no_active_duplicate(context):
    _,c,a,b,_,admin,pa,pb,*_=context
    body={'profile_a_id':pa['id'],'profile_b_id':pb['id'],'profile_a_version':pa['version'],'profile_b_version':pb['version']}
    assert c.post('/api/v1/admin/proposals',headers=a,json=body).status_code==403
    assert c.post('/api/v1/admin/proposals',headers=admin,json={**body,'profile_b_id':pa['id']}).status_code==422
    assert c.post('/api/v1/admin/proposals',headers=admin,json={**body,'profile_a_version':1}).status_code==409
    p=create(context)
    assert c.post('/api/v1/admin/proposals',headers=admin,json=body).status_code==409
    closed=c.post(f"/api/v1/admin/proposals/{p['id']}/cancel",headers=admin,json={'version':p['version'],'reason':'PRIVATE ADMIN NOTE'})
    assert closed.status_code==200
    assert 'PRIVATE ADMIN NOTE' not in c.get(f"/api/v1/proposals/{p['id']}",headers=a).text
    assert c.post('/api/v1/admin/proposals',headers=admin,json=body).status_code==201


def test_same_account_and_pending_profiles_cannot_receive_proposals(context):
    _,c,a,b,_,admin,pa,pb,*_=context
    c.put(f"/api/v1/admin/profiles/{pb['id']}/account",headers=admin,json={'version':pb['version'],'email':'one@example.test'})
    pb=c.get(f"/api/v1/profiles/{pb['id']}",headers=admin).json()
    body={'profile_a_id':pa['id'],'profile_b_id':pb['id'],'profile_a_version':pa['version'],'profile_b_version':pb['version']}
    assert c.post('/api/v1/admin/proposals',headers=admin,json=body).status_code==422
    c.put(f"/api/v1/admin/profiles/{pb['id']}/verification",headers=admin,json={'version':pb['version'],'status':'PENDING_VERIFICATION'})
    assert c.post('/api/v1/admin/proposals',headers=admin,json=body).status_code==422


def test_partial_or_arbitrary_sharing_is_rejected_and_integrity_is_checked(context):
    engine,c,a,b,out,admin,pa,pb,da,db,root=context;p=mutual(context)
    endpoint=f"/api/v1/admin/proposals/{p['id']}/sharing"
    assert c.post(endpoint,headers=admin,json={'version':p['version'],'document_ids':[da['id']]}).status_code==422
    assert c.post(endpoint,headers=admin,json={'version':p['version'],'document_ids':[da['id'],str(uuid4())]}).status_code==422
    authorise(context,p)
    with engine.connect() as connection:key=connection.execute(select(m.documents.c.storage_key).where(m.documents.c.id==UUID(db['id']))).scalar_one()
    (root/key).write_bytes(b'tampered')
    assert c.get(f"/api/v1/proposals/{p['id']}/documents/{db['id']}/download",headers=a).status_code==409


def test_notifications_are_private_idempotent_and_capture_workflow_events(context):
    _,c,a,b,out,admin,*_=context;p=mutual(context);authorise(context,p)
    result=c.get('/api/v1/notifications',headers=a).json()
    events={r['event'] for r in result['items']}
    assert {'NEW_PROPOSAL','PROPOSAL_ACCEPTED','MUTUAL_ACCEPTANCE','BIODATA_SHARED'}<=events
    notice=next(r for r in result['items'] if r['event']=='NEW_PROPOSAL')
    url=f"/api/v1/notifications/{notice['id']}/read"
    assert c.put(url,headers=out).status_code==404
    first=c.put(url,headers=a);second=c.put(url,headers=a)
    assert first.status_code==200 and first.json()['read_at']==second.json()['read_at']
    assert c.get('/api/v1/notifications?unread=true',headers=a).json()['unread_count']==result['unread_count']-1


def test_sharing_racing_with_profile_edit_never_leaves_active_access(context):
    engine,c,a,b,_,admin,pa,pb,da,db,_=context;p=mutual(context)
    def act(operation):
        client=TestClient(app)
        if operation=='share':return client.post(f"/api/v1/admin/proposals/{p['id']}/sharing",headers=admin,
            json={'version':p['version'],'document_ids':[da['id'],db['id']]}).status_code
        return client.put(f"/api/v1/profiles/{pa['id']}",headers=a,json={'version':pa['version'],'full_name':'Edited','gender':'FEMALE','date_of_birth':'1996-05-12'}).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(act,['share','edit']))
    assert results[0] in (200,409) and results[1]==200
    assert c.get(f"/api/v1/proposals/{p['id']}",headers=b).json()['status']=='CANCELLED'
    assert c.get(f"/api/v1/proposals/{p['id']}/documents/{da['id']}/download",headers=b).status_code==404
    with engine.connect() as connection:assert all(connection.execute(select(m.sharing.c.revoked_at)).scalars())


def test_concurrent_duplicate_creation_produces_one_proposal(context):
    engine,c,a,b,_,admin,pa,pb,*_=context
    body={'profile_a_id':pa['id'],'profile_b_id':pb['id'],'profile_a_version':pa['version'],'profile_b_version':pb['version']}
    with ThreadPoolExecutor(max_workers=2) as pool:
        statuses=list(pool.map(lambda _:TestClient(app).post('/api/v1/admin/proposals',headers=admin,json=body).status_code,range(2)))
    assert sorted(statuses)==[201,409]
    with engine.connect() as connection:
        assert len(connection.execute(select(m.proposals)).all())==1
        assert len(connection.execute(select(m.notifications).where(m.notifications.c.event=='NEW_PROPOSAL')).all())==2


def test_concurrent_opposite_choices_for_one_party_record_only_one(context):
    engine,c,*_=context;p=create(context)
    with ThreadPoolExecutor(max_workers=2) as pool:
        statuses=list(pool.map(lambda choice:respond(context,p,'a',choice).status_code,['ACCEPTED','REJECTED']))
    assert sorted(statuses)==[200,409]
    with engine.connect() as connection:assert len(connection.execute(select(m.responses)).all())==1

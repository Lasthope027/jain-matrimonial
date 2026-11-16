from datetime import date
import hashlib
import hmac
from typing import Annotated,Literal
from uuid import UUID
from fastapi import APIRouter,Depends,HTTPException,Query
from fastapi.responses import FileResponse
from pydantic import BaseModel,ConfigDict,Field
from sqlalchemy import select,insert,update,func,or_,cast,String,exists
from app import models as m
from app.auth import current_user,require_role,rate_limit
from app.db import get_engine
from app.documents import metadata,file_path
from app.workflow import lock_workflow,notify_parties,audit,cancel,ACTIVE

router=APIRouter(prefix='/api/v1',tags=['proposals and sharing'])
User=Annotated[dict,Depends(current_user)]
Admin=Annotated[dict,Depends(require_role('ADMINISTRATOR'))]
Customer=Annotated[dict,Depends(require_role('CUSTOMER'))]
Status=Literal['PENDING','REJECTED','MUTUALLY_ACCEPTED','CANCELLED']


class Strict(BaseModel):
    model_config=ConfigDict(extra='forbid')


class Create(Strict):
    profile_a_id:UUID
    profile_b_id:UUID
    profile_a_version:int=Field(ge=1)
    profile_b_version:int=Field(ge=1)


class Respond(Strict):
    profile_id:UUID
    response:Literal['ACCEPTED','REJECTED']


class Share(Strict):
    version:int=Field(ge=1)
    document_ids:list[UUID]=Field(min_length=1,max_length=40)


class Close(Strict):
    version:int=Field(ge=1)
    reason:str=Field(min_length=1,max_length=500)
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)


def party(connection,profile_id):
    query=select(m.profiles,m.account_profiles.c.account_id.label('owner_id'),m.users.c.active.label('owner_active'),
        m.users.c.email.label('owner_email'),m.roles.c.name.label('owner_role')).select_from(
        m.profiles.outerjoin(m.account_profiles,m.account_profiles.c.profile_id==m.profiles.c.id)
        .outerjoin(m.users,m.users.c.id==m.account_profiles.c.account_id)
        .outerjoin(m.user_roles,m.user_roles.c.user_id==m.users.c.id)
        .outerjoin(m.roles,m.roles.c.id==m.user_roles.c.role_id)).where(m.profiles.c.id==profile_id)
    return connection.execute(query).mappings().first()


def preview(connection,profile):
    today=date.today();birth=profile['date_of_birth']
    education=connection.execute(select(m.education.c.qualification,m.education.c.profession).where(m.education.c.profile_id==profile['id'])).mappings().first()
    return {'age':today.year-birth.year-((today.month,today.day)<(birth.month,birth.day)),
        'height_cm':profile['height_cm'],'community':profile['community'],'location':profile['current_location'],
        'education':education['qualification'] if education else None,'profession':education['profession'] if education else None}


def eligible(connection,proposal):
    for side in ('a','b'):
        p=party(connection,proposal['profile_'+side+'_id'])
        if not p or p['status']!='APPROVED' or p['version']!=proposal['profile_'+side+'_version'] or not p['owner_active'] or p['owner_role']!='CUSTOMER' or p['owner_id']!=proposal['account_'+side+'_id']:
            return False
    return proposal['account_a_id'] is not None and proposal['account_a_id']!=proposal['account_b_id']


def get(connection,proposal_id,user,*,locked=False):
    query=select(m.proposals).where(m.proposals.c.id==proposal_id)
    if user['role']!='ADMINISTRATOR':
        query=query.where(or_(m.proposals.c.account_a_id==UUID(user['id']),m.proposals.c.account_b_id==UUID(user['id'])))
    if locked:query=query.with_for_update()
    row=connection.execute(query).mappings().first()
    if not row:raise HTTPException(404,'Proposal not found')
    return row


def responses(connection,proposal):
    return {r['profile_id']:dict(r) for r in connection.execute(select(m.responses).where(m.responses.c.proposal_id==proposal['id'])).mappings()}


def both_accepted(connection,proposal):
    rows=responses(connection,proposal)
    return all(rows.get(proposal['profile_'+s+'_id'],{}).get('response')=='ACCEPTED' and
        rows[proposal['profile_'+s+'_id']]['responded_by']==proposal['account_'+s+'_id'] for s in ('a','b'))


def serialise(connection,row,user):
    result={k:row[k] for k in ('id','version','status','created_at','updated_at','closed_at')}
    replies=responses(connection,row)
    valid=eligible(connection,row) if row['status'] in ACTIVE else False
    if user['role']=='ADMINISTRATOR':
        result.update(closure_reason=row['closure_reason'],created_by=row['created_by'],eligible=valid,
            responses=[{k:r[k] for k in ('profile_id','response','responded_by','created_at')} for r in replies.values()])
        result['profiles']=[]
        for side in ('a','b'):
            p=party(connection,row['profile_'+side+'_id'])
            result['profiles'].append({'id':row['profile_'+side+'_id'],'full_name':p['full_name'],
                'status':p['status'],'version':p['version'],'snapshot_version':row['profile_'+side+'_version'],
                'account_email':p['owner_email'],'account_id':row['account_'+side+'_id']})
        result['documents']=[metadata(d) for d in connection.execute(select(m.documents).where(
            m.documents.c.profile_id.in_([row['profile_a_id'],row['profile_b_id']]),m.documents.c.deleted_at.is_(None))).mappings()]
        result['sharing_records']=[dict(r) for r in connection.execute(select(m.sharing,m.documents.c.original_name,
            m.users.c.email.label('authoriser_email')).join(m.documents,m.documents.c.id==m.sharing.c.document_id)
            .join(m.users,m.users.c.id==m.sharing.c.authorised_by).where(m.sharing.c.proposal_id==row['id']).order_by(m.sharing.c.created_at)).mappings()]
    else:
        side='a' if row['account_a_id']==UUID(user['id']) else 'b';other='b' if side=='a' else 'a'
        own=row['profile_'+side+'_id'];opposite=row['profile_'+other+'_id']
        own_response=replies.get(own,{}).get('response')
        result.update(own_profile={'id':own,'full_name':row['profile_'+side+'_name']},match=row['preview_'+other] or {},
            own_response=own_response,other_response=replies.get(opposite,{}).get('response'),
            can_respond=valid and row['status']=='PENDING' and own_response is None,
            closure_reason='This proposal was closed by the consultancy or because eligibility changed.' if row['status']=='CANCELLED' else None)
        result['shared_documents']=[]
        if valid and row['status']=='MUTUALLY_ACCEPTED' and both_accepted(connection,row):
            query=select(m.documents,m.sharing.c.created_at.label('authorised_at')).join(m.sharing,m.sharing.c.document_id==m.documents.c.id).where(
                m.sharing.c.proposal_id==row['id'],m.sharing.c.recipient_profile_id==own,
                m.sharing.c.recipient_account_id==UUID(user['id']),m.sharing.c.revoked_at.is_(None),
                m.documents.c.deleted_at.is_(None),m.documents.c.profile_id==opposite)
            for d in connection.execute(query).mappings():
                item=metadata(d);item.pop('profile_id');item['authorised_at']=d['authorised_at'];result['shared_documents'].append(item)
    return result


def listing(connection,user,status,offset,limit,*,profile_id=None,q=None,shared_only=False):
    query=select(m.proposals)
    if user['role']!='ADMINISTRATOR':
        a=m.proposals.c.account_a_id==UUID(user['id']);b=m.proposals.c.account_b_id==UUID(user['id'])
        if profile_id:a=a & (m.proposals.c.profile_a_id==profile_id);b=b & (m.proposals.c.profile_b_id==profile_id)
        query=query.where(or_(a,b))
    elif q:
        query=query.where(or_(m.proposals.c.profile_a_name.icontains(q,autoescape=True),
            m.proposals.c.profile_b_name.icontains(q,autoescape=True),cast(m.proposals.c.id,String).icontains(q,autoescape=True)))
    if status:query=query.where(m.proposals.c.status==status)
    if shared_only:
        query=query.where(m.proposals.c.status=='MUTUALLY_ACCEPTED',exists(select(m.sharing.c.id).where(
            m.sharing.c.proposal_id==m.proposals.c.id,m.sharing.c.recipient_account_id==UUID(user['id']),m.sharing.c.revoked_at.is_(None))))
    total=connection.execute(select(func.count()).select_from(query.subquery())).scalar_one()
    rows=connection.execute(query.order_by(m.proposals.c.created_at.desc(),m.proposals.c.id).offset(offset).limit(limit+1)).mappings().all()
    return {'items':[serialise(connection,r,user) for r in rows[:limit]],'total':total,'next_offset':offset+limit if len(rows)>limit else None}


@router.get('/proposals')
def customer_list(user:Customer,status:Status|None=None,profile_id:UUID|None=None,shared_only:bool=False,offset:int=Query(0,ge=0),limit:int=Query(20,ge=1,le=50)):
    with get_engine().connect() as c:return listing(c,user,status,offset,limit,profile_id=profile_id,shared_only=shared_only)


@router.get('/admin/proposals')
def admin_list(user:Admin,status:Status|None=None,q:str|None=Query(None,max_length=200),offset:int=Query(0,ge=0),limit:int=Query(20,ge=1,le=50)):
    with get_engine().connect() as c:return listing(c,user,status,offset,limit,q=q.strip() if q else None)


@router.get('/proposals/{proposal_id}')
def detail(proposal_id:UUID,user:User):
    with get_engine().connect() as c:return serialise(c,get(c,proposal_id,user),user)


@router.post('/admin/proposals',status_code=201)
def create(body:Create,user:Admin):
    if body.profile_a_id==body.profile_b_id:raise HTTPException(422,'Select two different profiles')
    ordered=sorted([(body.profile_a_id,body.profile_a_version),(body.profile_b_id,body.profile_b_version)])
    with get_engine().begin() as c:
        lock_workflow(c)
        a,b=[party(c,pid) for pid,_ in ordered]
        if any(not p or p['status']!='APPROVED' or not p['owner_active'] or p['owner_role']!='CUSTOMER' for p in (a,b)):
            raise HTTPException(422,'Both profiles must be approved and linked to active customer accounts')
        if a['owner_id']==b['owner_id']:raise HTTPException(422,'Independent responses require two different customer accounts')
        if a['version']!=ordered[0][1] or b['version']!=ordered[1][1]:raise HTTPException(409,'A profile changed. Reload both profiles before proposing.')
        if c.execute(select(m.proposals.c.id).where(m.proposals.c.profile_a_id==a['id'],m.proposals.c.profile_b_id==b['id'],m.proposals.c.status.in_(ACTIVE))).first():
            raise HTTPException(409,'An active proposal already exists for this pair')
        row=c.execute(insert(m.proposals).values(profile_a_id=a['id'],profile_b_id=b['id'],account_a_id=a['owner_id'],account_b_id=b['owner_id'],
            profile_a_version=a['version'],profile_b_version=b['version'],profile_a_name=a['full_name'],profile_b_name=b['full_name'],
            preview_a=preview(c,a),preview_b=preview(c,b),created_by=UUID(user['id'])).returning(m.proposals)).mappings().one()
        audit(c,user['id'],'PROPOSAL_CREATED',row['id'])
        notify_parties(c,row,'NEW_PROPOSAL','A new consultancy-selected proposal is ready for your response.')
        return serialise(c,row,user)


@router.post('/proposals/{proposal_id}/responses')
def respond(proposal_id:UUID,body:Respond,user:Customer):
    rate_limit('proposal-response',user['id'],120,3600)
    failure=None;result=None
    with get_engine().begin() as c:
        lock_workflow(c);row=get(c,proposal_id,user,locked=True)
        side='a' if row['account_a_id']==UUID(user['id']) else 'b'
        if body.profile_id!=row['profile_'+side+'_id']:raise HTTPException(403,'Respond only for your own proposed profile')
        previous=responses(c,row).get(body.profile_id)
        if previous:
            if previous['response']!=body.response:raise HTTPException(409,'A response is already recorded and cannot be changed')
            return serialise(c,row,user)
        if row['status']!='PENDING':raise HTTPException(409,'This proposal is no longer awaiting responses')
        if not eligible(c,row):
            cancel(c,row,user['id'],'Eligibility or consent snapshot changed');failure='Profile eligibility changed. The proposal was closed.'
        else:
            c.execute(insert(m.responses).values(proposal_id=proposal_id,profile_id=body.profile_id,responded_by=UUID(user['id']),response=body.response))
            new_status='REJECTED' if body.response=='REJECTED' else ('MUTUALLY_ACCEPTED' if both_accepted(c,row) else 'PENDING')
            c.execute(update(m.proposals).where(m.proposals.c.id==proposal_id).values(status=new_status,version=row['version']+1))
            audit(c,user['id'],'PROPOSAL_'+body.response,proposal_id,{'profile_id':str(body.profile_id)})
            notify_parties(c,row,'PROPOSAL_'+body.response,'A response has been recorded on your proposal.')
            if new_status=='MUTUALLY_ACCEPTED':notify_parties(c,row,'MUTUAL_ACCEPTANCE','Both parties accepted. Biodata access awaits consultancy authorisation.')
            result=serialise(c,get(c,proposal_id,user),user)
    if failure:raise HTTPException(409,failure)
    return result


@router.post('/admin/proposals/{proposal_id}/cancel')
def close(proposal_id:UUID,body:Close,user:Admin):
    with get_engine().begin() as c:
        lock_workflow(c);row=get(c,proposal_id,user,locked=True)
        if row['version']!=body.version:raise HTTPException(409,'Proposal changed. Reload before closing.')
        if row['status'] not in ACTIVE:raise HTTPException(409,'This proposal is already final')
        cancel(c,row,user['id'],body.reason)
        return serialise(c,get(c,proposal_id,user),user)


def intact(document,expected=None):
    path=file_path(document['storage_key'])
    try:
        with path.open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
    except OSError:raise HTTPException(404,'Document not found') from None
    if not hmac.compare_digest(digest,expected or document['sha256']):raise HTTPException(409,'Document content changed. Contact the consultancy.')
    return path


@router.post('/admin/proposals/{proposal_id}/sharing')
def share(proposal_id:UUID,body:Share,user:Admin):
    failure=None;result=None
    with get_engine().begin() as c:
        lock_workflow(c);row=get(c,proposal_id,user,locked=True)
        if row['status']!='MUTUALLY_ACCEPTED' or not both_accepted(c,row):raise HTTPException(409,'Biodata requires both parties to accept first')
        if not eligible(c,row):
            cancel(c,row,user['id'],'Eligibility or consent snapshot changed');failure='Profile eligibility changed. The proposal was closed.'
        else:
            chosen=set(body.document_ids)
            docs=c.execute(select(m.documents).where(m.documents.c.id.in_(chosen),m.documents.c.deleted_at.is_(None),
                m.documents.c.profile_id.in_([row['profile_a_id'],row['profile_b_id']]))).mappings().all()
            if len(docs)!=len(chosen):raise HTTPException(422,'Select current documents belonging to the two proposed profiles')
            existing=c.execute(select(m.sharing).where(m.sharing.c.proposal_id==proposal_id,m.sharing.c.revoked_at.is_(None))).mappings().all()
            existing_ids={r['document_id'] for r in existing}
            new=[d for d in docs if d['id'] not in existing_ids]
            if new and row['version']!=body.version:raise HTTPException(409,'Proposal changed. Reload before authorising sharing.')
            combined=chosen|existing_ids
            biodata=set(c.execute(select(m.documents.c.profile_id).where(m.documents.c.id.in_(combined),m.documents.c.kind=='BIODATA',m.documents.c.deleted_at.is_(None))).scalars())
            if biodata!={row['profile_a_id'],row['profile_b_id']}:raise HTTPException(422,'Select at least one biodata document from each profile')
            for d in new:
                intact(d)
                recipient='b' if d['profile_id']==row['profile_a_id'] else 'a'
                c.execute(insert(m.sharing).values(proposal_id=proposal_id,document_id=d['id'],recipient_profile_id=row['profile_'+recipient+'_id'],
                    recipient_account_id=row['account_'+recipient+'_id'],authorised_by=UUID(user['id']),document_sha256=d['sha256']))
            if new:
                c.execute(update(m.proposals).where(m.proposals.c.id==proposal_id).values(version=row['version']+1))
                audit(c,user['id'],'BIODATA_SHARING_AUTHORISED',proposal_id,{'document_ids':[str(d['id']) for d in new]})
                notify_parties(c,row,'BIODATA_SHARED','The consultancy authorised selected biodata for your mutually accepted proposal.')
            result=serialise(c,get(c,proposal_id,user),user)
    if failure:raise HTTPException(409,failure)
    return result


@router.get('/proposals/{proposal_id}/documents/{document_id}/download')
def shared_download(proposal_id:UUID,document_id:UUID,user:Customer):
    with get_engine().begin() as c:
        lock_workflow(c);row=get(c,proposal_id,user)
        if row['status']!='MUTUALLY_ACCEPTED' or not eligible(c,row) or not both_accepted(c,row):raise HTTPException(404,'Shared document not found')
        side='a' if row['account_a_id']==UUID(user['id']) else 'b';other='b' if side=='a' else 'a'
        grant=c.execute(select(m.sharing).where(m.sharing.c.proposal_id==proposal_id,m.sharing.c.document_id==document_id,
            m.sharing.c.recipient_profile_id==row['profile_'+side+'_id'],m.sharing.c.recipient_account_id==UUID(user['id']),m.sharing.c.revoked_at.is_(None))).mappings().first()
        doc=c.execute(select(m.documents).where(m.documents.c.id==document_id,m.documents.c.profile_id==row['profile_'+other+'_id'],m.documents.c.deleted_at.is_(None))).mappings().first()
        if not grant or not doc or not grant['document_sha256']:raise HTTPException(404,'Shared document not found')
        path=intact(doc,grant['document_sha256'])
        audit(c,user['id'],'SHARED_BIODATA_DOWNLOADED',proposal_id,{'document_id':str(document_id),'sharing_record_id':str(grant['id'])})
        return FileResponse(path,media_type=doc['media_type'],filename=doc['original_name'],content_disposition_type='attachment',headers={'Content-Security-Policy':"sandbox; default-src 'none'"})

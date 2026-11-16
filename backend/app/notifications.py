from uuid import UUID
from typing import Annotated
from fastapi import APIRouter,Depends,HTTPException,Query
from sqlalchemy import select,update,func
from app import models as m
from app.auth import current_user,now
from app.db import get_engine

router=APIRouter(prefix='/api/v1/notifications',tags=['notifications'])
User=Annotated[dict,Depends(current_user)]


@router.get('')
def listing(user:User,unread:bool=False,offset:int=Query(0,ge=0),limit:int=Query(30,ge=1,le=100)):
    with get_engine().connect() as c:
        query=select(m.notifications).where(m.notifications.c.user_id==UUID(user['id']))
        count=c.execute(select(func.count()).select_from(m.notifications).where(m.notifications.c.user_id==UUID(user['id']),m.notifications.c.read_at.is_(None))).scalar_one()
        if unread:query=query.where(m.notifications.c.read_at.is_(None))
        total=c.execute(select(func.count()).select_from(query.subquery())).scalar_one()
        rows=c.execute(query.order_by(m.notifications.c.created_at.desc(),m.notifications.c.id).offset(offset).limit(limit+1)).mappings().all()
        return {'items':[{k:r[k] for k in ('id','event','message','read_at','created_at','proposal_id','profile_id')} for r in rows[:limit]],
            'total':total,'unread_count':count,'next_offset':offset+limit if len(rows)>limit else None}


@router.put('/{notification_id}/read')
def read(notification_id:UUID,user:User):
    with get_engine().begin() as c:
        row=c.execute(update(m.notifications).where(m.notifications.c.id==notification_id,m.notifications.c.user_id==UUID(user['id']))
            .values(read_at=func.coalesce(m.notifications.c.read_at,now())).returning(m.notifications.c.id,m.notifications.c.read_at)).mappings().first()
        if not row:raise HTTPException(404,'Notification not found')
        return dict(row)

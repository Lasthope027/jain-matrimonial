from email.message import EmailMessage
import smtplib
import ssl
from app.config import Settings


def send_otp(settings: Settings, email: str, code: str) -> None:
    if not settings.smtp_host or not settings.smtp_from:
        raise ValueError('SMTP is not configured')
    message = EmailMessage()
    message['Subject'] = 'Your Jain Matrimonial sign-in code'
    message['From'] = settings.smtp_from
    message['To'] = email
    message.set_content(f'Your sign-in code is {code}. It expires in five minutes. If you did not request it, ignore this email.')
    context = ssl.create_default_context()
    factory = smtplib.SMTP_SSL if settings.smtp_security == 'ssl' else smtplib.SMTP
    kwargs = {'timeout': 10, 'local_hostname': 'jain-matrimonial'}
    if settings.smtp_security == 'ssl':
        kwargs['context'] = context
    with factory(settings.smtp_host, settings.smtp_port, **kwargs) as smtp:
        if settings.smtp_security == 'starttls':
            smtp.ehlo()
            smtp.starttls(context=context)
            smtp.ehlo()
        if settings.smtp_username:
            smtp.login(settings.smtp_username, settings.smtp_password.get_secret_value())
        smtp.send_message(message)

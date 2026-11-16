from datetime import date
from decimal import Decimal
from typing import Annotated, Literal
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator
from app.auth import EmailInput

Short = Annotated[str, Field(max_length=200)]
Long = Annotated[str, Field(max_length=4000)]
ChoiceList = Annotated[list[Annotated[str, Field(min_length=1, max_length=200)]], Field(max_length=30)]


class StrictModel(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)


class Education(StrictModel):
    qualification: Short | None = None
    college: Short | None = None
    profession: Short | None = None
    company: Short | None = None
    employment_location: Short | None = None
    annual_income: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)


class Family(StrictModel):
    father_name: Short | None = None
    father_occupation: Short | None = None
    mother_name: Short | None = None
    mother_occupation: Short | None = None
    siblings: int | None = Field(default=None, ge=0, le=30)
    family_location: Short | None = None
    additional_information: Long | None = None


class Preferences(StrictModel):
    age_min: int | None = Field(default=None, ge=18, le=100)
    age_max: int | None = Field(default=None, ge=18, le=100)
    height_min_cm: int | None = Field(default=None, ge=50, le=300)
    height_max_cm: int | None = Field(default=None, ge=50, le=300)
    locations: ChoiceList = Field(default_factory=list)
    education: ChoiceList = Field(default_factory=list)
    professions: ChoiceList = Field(default_factory=list)
    communities: ChoiceList = Field(default_factory=list)
    marital_statuses: ChoiceList = Field(default_factory=list)
    additional_expectations: Long | None = None

    @model_validator(mode='after')
    def ranges(self):
        for low, high in ((self.age_min, self.age_max), (self.height_min_cm, self.height_max_cm)):
            if low is not None and high is not None and low > high:
                raise ValueError('Minimum must not exceed maximum')
        return self


class ProfileData(StrictModel):
    full_name: str = Field(min_length=1, max_length=200)
    gender: Literal['MALE', 'FEMALE', 'OTHER']
    date_of_birth: date
    height_cm: int | None = Field(default=None, ge=50, le=300)
    marital_status: Literal['NEVER_MARRIED', 'DIVORCED', 'WIDOWED', 'SEPARATED'] | None = None
    community: str | None = Field(default=None, max_length=100)
    sub_community: str | None = Field(default=None, max_length=100)
    mother_tongue: str | None = Field(default=None, max_length=80)
    current_location: Short | None = None
    native_place: Short | None = None
    education: Education = Field(default_factory=Education)
    family: Family = Field(default_factory=Family)
    preferences: Preferences = Field(default_factory=Preferences)

    @field_validator('date_of_birth')
    @classmethod
    def adult_profile(cls, value):
        today = date.today()
        age = today.year - value.year - ((today.month, today.day) < (value.month, value.day))
        if not 18 <= age <= 100:
            raise ValueError('Profiles must be for adults aged 18 to 100')
        return value


class AdminCreate(ProfileData):
    account_email: str | None = None
    status: Literal['PENDING_VERIFICATION', 'APPROVED'] = 'PENDING_VERIFICATION'

    @field_validator('account_email')
    @classmethod
    def email(cls, value):
        return EmailInput(email=value).email if value else None


class EditProfile(ProfileData):
    version: int = Field(ge=1)


class Association(StrictModel):
    version: int = Field(ge=1)
    email: str | None = None

    @field_validator('email')
    @classmethod
    def valid_email(cls, value):
        return EmailInput(email=value).email if value else None


class Verification(StrictModel):
    version: int = Field(ge=1)
    status: Literal['PENDING_VERIFICATION', 'APPROVED', 'REJECTED', 'INACTIVE']
    note: str | None = Field(default=None, max_length=1000)

    @model_validator(mode='after')
    def rejection_reason(self):
        if self.status == 'REJECTED' and not self.note:
            raise ValueError('A rejection reason is required')
        return self

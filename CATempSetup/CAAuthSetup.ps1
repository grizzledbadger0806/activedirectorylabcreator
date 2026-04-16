Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools
Install-AdcsCertificationAuthority -CAType EnterpriseRootCA -CACommonName "LAB-CA" -KeyLength 2048 -HashAlgorithm SHA256 -ValidityPeriod Years -ValidityPeriodUnits 10
Install-WindowsFeature ADCS-Web-Enrollment -IncludeManagementTools
Install-AdcsWebEnrollment
certutil -config - -ping
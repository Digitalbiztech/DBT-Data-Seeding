# Sample API Callouts - DBT Data Seeding

The application makes callouts strictly to standard Salesforce APIs (SOAP and REST) on remote Salesforce instances. Below are sample requests and responses for the primary callouts used.

---

## 1. Authentication (SOAP Login)

Used by `ExternalOrgAuthService.cls` to obtain a Session ID for the remote org.

**HTTP Request**
```http
POST /services/Soap/u/58.0 HTTP/1.1
Host: login.salesforce.com
Content-Type: text/xml; charset=UTF-8
SOAPAction: login

<?xml version="1.0" encoding="utf-8"?>
<env:Envelope xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">
    <env:Body>
        <n1:login xmlns:n1="urn:partner.soap.sforce.com">
            <n1:username>user@sourceorg.com</n1:username>
            <n1:password>passwordAndSecurityToken</n1:password>
        </n1:login>
    </env:Body>
</env:Envelope>
```

**HTTP Response**
```http
HTTP/1.1 200 OK
Content-Type: text/xml; charset=UTF-8

<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="urn:partner.soap.sforce.com">
   <soapenv:Body>
      <loginResponse>
         <result>
            <metadataServerUrl>https://instance.salesforce.com/services/Soap/m/58.0/00D...</metadataServerUrl>
            <passwordExpired>false</passwordExpired>
            <sandbox>false</sandbox>
            <serverUrl>https://instance.salesforce.com/services/Soap/u/58.0/00D...</serverUrl>
            <sessionId>00D...!AQEAQ...</sessionId>
            <userId>005...</userId>
         </result>
      </loginResponse>
   </soapenv:Body>
</soapenv:Envelope>
```

---

## 2. Remote SOQL Query (REST API)

Used by `ExternalOrgQueryService.cls` to extract data from the Source Org.

**HTTP Request**
```http
GET /services/data/v58.0/query/?q=SELECT+Id,Name,Industry+FROM+Account+LIMIT+200 HTTP/1.1
Host: your-source-instance.salesforce.com
Authorization: Bearer 00D...!AQEAQ...
Accept: application/json
```

**HTTP Response**
```http
HTTP/1.1 200 OK
Content-Type: application/json;charset=UTF-8

{
  "totalSize": 2,
  "done": true,
  "records": [
    {
      "attributes": {
        "type": "Account",
        "url": "/services/data/v58.0/sobjects/Account/001RM000003abcdYAA"
      },
      "Id": "001RM000003abcdYAA",
      "Name": "Sample Account 1",
      "Industry": "Technology"
    },
    {
      "attributes": {
        "type": "Account",
        "url": "/services/data/v58.0/sobjects/Account/001RM000003efghYAA"
      },
      "Id": "001RM000003efghYAA",
      "Name": "Sample Account 2",
      "Industry": "Finance"
    }
  ]
}
```

---

## 3. Data Insertion (REST Composite Tree API)

Used by `ExternalOrgDmlService.cls` to push records into the Destination Org in bulk.

**HTTP Request**
```http
POST /services/data/v58.0/composite/tree/Account HTTP/1.1
Host: your-destination-instance.salesforce.com
Authorization: Bearer 00D...!XYZ...
Content-Type: application/json

{
  "records": [
    {
      "attributes": {
        "type": "Account",
        "referenceId": "ref1"
      },
      "Name": "Sample Account 1",
      "Industry": "Technology"
    },
    {
      "attributes": {
        "type": "Account",
        "referenceId": "ref2"
      },
      "Name": "Sample Account 2",
      "Industry": "Finance"
    }
  ]
}
```

**HTTP Response**
```http
HTTP/1.1 201 Created
Content-Type: application/json;charset=UTF-8

{
  "hasErrors": false,
  "results": [
    {
      "referenceId": "ref1",
      "id": "001Dest0000001AAA"
    },
    {
      "referenceId": "ref2",
      "id": "001Dest0000002AAA"
    }
  ]
}
```

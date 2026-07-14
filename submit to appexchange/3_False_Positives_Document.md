# Checkmarx False Positives Documentation

**App Name:** DBT Data Seeding
**Date:** [Insert Date]
**Checkmarx Report ID:** phxcxmanwp001_39250

The following vulnerabilities have been flagged by the Checkmarx Scanner. Because our application is a dynamic administrative tool designed to migrate configuration and data between arbitrary Salesforce Orgs, these are structural false positives.

Below is the detailed justification for the AppExchange Security Review team.

## 1. Apex AuthN SECRETS (18 Findings)

**Vulnerability Type:** Hardcoded/Cleartext Credentials in memory
**Locations:** `ExternalOrgAuthService.cls`, `ExternalOrgQueryController.cls`, `ExternalOrgDescribeService.cls`

**Why it is a False Positive:**
The core functionality of this application requires establishing a real-time connection to a remote Salesforce Org.

- The user inputs their `username` and `password` via the LWC UI.
- These credentials are passed to the Apex backend to execute an immediate SOAP Login callout (`ExternalOrgAuthService.login()`).
- The resulting `sessionId` is passed into subsequent REST API callouts to authorize data extraction and insertion.
- **Security Control:** The credentials and the session ID are held strictly in-memory during the execution context. They are **never** persistently stored in the database, logged in debug statements, or exposed back to the client. This is the intended and secure design for an app of this nature pending the implementation of Named Credentials.

## 2. Apex SOQL SOSL SECURITY ENFORCED USAGE / USER MODE MISSING (12 Findings)

**Vulnerability Type:** FLS / CRUD Enforcement Missing
**Locations:** `DataSeedingBatch.cls`, `ExternalOrgDmlService.cls`, `DataSeedingService.cls`

**Why it is a False Positive:**

- **Dynamic Local Operations:** The application dynamically seeds user-selected objects. We cannot statically assert `Schema.sObjectType.Account.isCreateable()` because the object name is passed as a string at runtime.
- **Security Control:** For any local queries or DML, we explicitly utilize the overloaded database methods with User Mode enforcement:
  - `Database.query(soql, AccessLevel.USER_MODE)`
  - `Database.insert(records, dmlOptions, AccessLevel.USER_MODE)`
  - Checkmarx frequently flags dynamic DML or fails to recognize the newer `AccessLevel.USER_MODE` signatures when combined with `DMLOptions`.
- **Remote Operations:** The vast majority of operations occur against a remote org via the Salesforce REST API. In these cases, FLS and CRUD are natively and implicitly enforced by the target org's profile and permission set assigned to the authenticated integration user.

## 3. SOQL SOSL Injection (3 Findings)

**Vulnerability Type:** SOQL Injection
**Locations:** `DataSeedingService.cls`

**Why it is a False Positive:**
The application dynamically constructs SOQL strings to query the selected source objects (e.g., `SELECT ... FROM [dynamicObject] WHERE ...`).

- **Security Control:** To prevent SOQL injection, all object names and field names are strictly validated against a regex pattern (`^[a-zA-Z0-9_]+$`) before being appended to the query string.
- Any dynamic values placed into the `WHERE` clause (e.g., matching old IDs) are explicitly escaped using `String.escapeSingleQuotes(value)` before concatenation.
- Checkmarx flags the dynamic concatenation, but the comprehensive regex validation and native escaping mechanisms ensure that malicious injection is impossible.

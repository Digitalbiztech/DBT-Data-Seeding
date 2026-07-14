# Security Scanner Reports - Action Required

As the developer, you must run the following scanners before your final AppExchange submission. Since this is a native Salesforce application with Apex and LWC, you cannot bypass this step.

### 1. Salesforce Code Analyzer (SFCA)
You must run the Salesforce Code Analyzer on your project directory. 
**Command to run locally:**
```bash
sf scanner run --format csv --outfile sfca_report.csv --target "force-app"
```
*Action:* Run this command, resolve any critical issues, and upload the resulting `sfca_report.csv` (or PDF) to the AppExchange submission portal under **Salesforce Code Analyzer**.

### 2. Checkmarx Source Code Scanner
You must log into the Salesforce Partner Security Portal and initiate a Checkmarx scan against your packaging org or a linked repository.
*Action:* Once the scan completes, download the PDF report. You must upload this clean report under **Security Scanner Reports**.

---

### False Positives Documentation (Template)

If the Checkmarx or SFCA reports flag issues that are not actual security vulnerabilities in the context of this app (False Positives), you must explain them in a document. Below is a template you can use to create `3_False_Positives_Document.doc`.

---

**App Name:** DBT Data Seeding
**Date:** [Insert Date]

| Scanner Name | File Name & Line Number | Vulnerability Type | Why it is a False Positive |
| :--- | :--- | :--- | :--- |
| Checkmarx | `ExternalOrgQueryService.cls` - Line X | SOQL Injection | The query string is constructed dynamically to query a remote org. Object and Field names are strictly validated against schema describes before query construction. No direct user input is concatenated into the WHERE clause without escaping. |
| Checkmarx | `ExternalOrgAuthService.cls` - Line Y | Hardcoded Credentials / Cleartext Storage | The username and password variables are decorated with `@track` or passed directly from the LWC UI into the Apex Controller. They are held in memory for the duration of the SOAP callout to establish a session and are never written to the database or logged. |
| SF Code Analyzer | `DataSeedingBatch.cls` - Line Z | CRUD/FLS Enforcement | The purpose of this tool is administrative data seeding between orgs. The target org's profile/permission set enforces CRUD/FLS natively via the REST API integration user, rather than explicitly checking `Schema.sObjectType...isAccessible()` in the runtime org context. |

*(Please modify the examples above to match the actual line numbers and flagged issues from your specific scanner reports).*

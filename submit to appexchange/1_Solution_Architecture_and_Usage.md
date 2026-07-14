# DBT Data Seeding - Solution Architecture and Usage

## 1. Solution Architecture

The DBT Data Seeding application is a 100% native Salesforce application designed to securely transfer data between two separate Salesforce environments (a "Source" org and a "Destination" org). It automatically handles the complex task of maintaining referential integrity (Lookups and Master-Detail relationships) during the transfer.

The application follows a Service-Oriented Architecture (SOA) and uses the Facade pattern:

- **Frontend Layer:** Built with Lightning Web Components (LWC). This provides the user interface for configuration, authentication, and execution monitoring.
- **Controller Layer:** The `ExternalOrgQueryController` serves as an Apex facade, exposing `@AuraEnabled` methods to the LWC frontend.
- **Service Layer (Backend):**
  - `ExternalOrgAuthService`: Manages SOAP-based authentication with remote orgs.
  - `ExternalOrgDescribeService`: Uses recursive REST/SOAP callouts to build a schema dependency tree, ensuring parent records are seeded before their children.
  - `ExternalOrgQueryService`: Executes remote SOQL against the Source org to fetch data.
  - `ExternalOrgDmlService`: Pushes records to the Destination org using the Salesforce REST Composite API for bulkified inserts.
  - `DataSeedingService`: Orchestrates the high-level logic.
- **Batch Layer:** `DataSeedingBatch` manages the iterative data transfer. It queries source records, maps their old Source IDs to the newly created Destination IDs in-memory (`idRemap`), and inserts them in topological order.

## 2. Information Flow & Data Touchpoints

1.  **User Input:** The user inputs credentials and selects objects via the LWC interface.
2.  **Authentication:** Apex makes a SOAP login callout to the Source and Destination orgs. The resulting Session IDs are held in memory.
3.  **Discovery:** Apex makes REST API describe callouts to the Source org to map object dependencies.
4.  **Extraction:** The Batch Apex job executes SOQL queries via REST callouts to the Source org.
5.  **Transformation:** Data is held in-memory in the runtime Org. Source IDs are remapped to Destination IDs.
6.  **Load:** Transformed data is sent to the Destination org via REST Composite API callouts.

**Data Touchpoints:** Data only exists in transit and in the runtime Apex memory space. No external databases, middleware, or platforms (like Heroku or AWS) are used. The application does not store the transferred data in the runtime org's database.

## 3. Encryption on Data Transfer

All data transfer and communication between the runtime Org, Source Org, and Destination Org occur exclusively over **HTTPS/TLS 1.2+**. This is enforced by Salesforce's standard platform security for callouts. The application does not use any non-secure (HTTP) endpoints.

## 4. Usage Instructions

### Prerequisites

1. **Salesforce CLI:** Installed (`sf` CLI v2 or later recommended).
2. **Access to Salesforce orgs:** Target org (to install package) and optionally a Dev Hub.
3. **User permissions:** API Enabled, Modify Metadata/Deploy, Assign Permission Sets, Read and Create on ContentVersion, and Object/field level permissions on seeded objects.
4. **Network and security:** Allowlist IPs or use a security token when logging in with username/password from the LWC. Ensure remote orgs permit API login.

### Installation & Setup

**Option A: Deploy source to an org**

1. Authenticate to the target org: `sf org login web --alias myTarget`
2. Deploy source: `sf project deploy start --target-org myTarget`
3. Assign permission set: `sfdx force:user:permset:assign -n Data_Seeding_Access -u myTarget`
4. Open the org: `sf org open --target-org myTarget`

**Option B: Install unlocked package into an org**

1. Identify a promoted SubscriberPackageVersionId (starts with `04t`). Promote if necessary using `sf package version promote`.
2. Authenticate to the target org: `sf org login web --alias myTarget`
3. Install the package: `sf package install --package 04tXXXXXXXXXXXX --target-org myTarget --wait 30`
4. Assign permission set: `sfdx force:user:permset:assign -n Data_Seeding_Access -u myTarget`
5. Open the org: `sf org open --target-org myTarget`

### Post-Installation

1. **Grant access:** Assign the `Data_Seeding_Access` permission set to users who will run data seeding.
2. **Make the LWC available:** Go to Setup > App Builder. Create or edit a Lightning App Page, Record Page, or Home Page, and drag the "External Org Query" component onto the canvas. Save and activate.
3. **Access the Lightning app:** Open the App Launcher and select the application named **Data Seed**.

### How To Use The UI

**1. Source and Destination org setup**

- Choose **Use Current Org** if the source/destination is the same org.
- Otherwise, enter **Username** and **Password** (append security token if required) and choose the Environment (Production/Sandbox) for remote orgs.
- Click **Test Connection** / **Test Destination Connection** to verify credentials.

**2. Object discovery and plan**

- Use **Search Objects** to select the root object to export.
- Configure dependency depth, exclude objects where needed, and review the dependency tree.
- Use **get required fields actions** to ensure mandatory fields are included.
- Review **createable fields** before attempting to insert into the destination.

**3. Query and preview**

- Enter SOQL (e.g., `SELECT Id, Name FROM Account LIMIT 10`) and click **Run Query** to validate access and data shape. Adjust fields and limits as needed.

**4. Data import and seeding**

- Choose whether to insert new or update existing records.
- Use the **seeding action** to start a batch job that handles pagination, reference resolution, and DML in the destination org.
- **Monitor progress:** The component polls the batch job status. When complete, download the generated seeding report (requires ContentVersion access).

### Apex-Based Usage (For Admins and Developers)

You can optionally run seeding via Apex scripts.

1. **Prepare tasks:**

```apex
List<Map<String, Object>> tasks = new List<Map<String, Object>>();
Map<String, Object> t = new Map<String, Object>();
t.put('objectName', 'Account');
t.put('soql', 'SELECT Id, Name, OwnerId FROM Account LIMIT 100');
t.put('fields', new List<String>{ 'Id', 'Name', 'OwnerId' });
tasks.add(t);
Map<String, Map<String, String>> planEdges = new Map<String, Map<String, String>>();
planEdges.put('Account', new Map<String, String>{ 'OwnerId' => 'User' });
```

2. **Start the batch:** `String jobId = DataSeedingService.startDataSeedingBatch(null, null, null, null, tasks, planEdges);`
3. **Monitor status:** `AsyncApexJob job = DataSeedingService.getBatchJobStatus(jobId);`
4. **Retrieve report:** `String csv = DataSeedingService.getBatchReport(jobId);`

### Common Errors and Resolutions

- **INVALID_LOGIN:** Wrong credentials, missing security token, or incorrect environment. Append the security token to the password if the IP is not allowlisted.
- **API_DISABLED:** Profile lacks API Enabled permission.
- **INSUFFICIENT_ACCESS:** Missing CRUD/FLS on objects/fields. Update profiles/permission sets.
- **REQUIRED_FIELD_MISSING:** Destination requires fields not in payload. Use "get required fields" in the UI.
- **Reference resolution failures:** Parent records not present in the destination. Increase dependency depth or seed parent objects first.
- **Mixed DML error:** Attempting DML on setup and non-setup objects simultaneously. Seed setup objects in a separate phase.

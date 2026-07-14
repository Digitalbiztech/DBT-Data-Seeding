# DBT Data Seeding - Solution Architecture and Usage

## 1. Solution Architecture

The DBT Data Seeding application is a 100% native Salesforce application designed to securely transfer data between two separate Salesforce environments (a "Source" org and a "Destination" org). It automatically handles the complex task of maintaining referential integrity (Lookups and Master-Detail relationships) during the transfer.

The application follows a Service-Oriented Architecture (SOA) and uses the Facade pattern:

*   **Frontend Layer:** Built with Lightning Web Components (LWC). This provides the user interface for configuration, authentication, and execution monitoring.
*   **Controller Layer:** The `ExternalOrgQueryController` serves as an Apex facade, exposing `@AuraEnabled` methods to the LWC frontend.
*   **Service Layer (Backend):**
    *   `ExternalOrgAuthService`: Manages SOAP-based authentication with remote orgs.
    *   `ExternalOrgDescribeService`: Uses recursive REST/SOAP callouts to build a schema dependency tree, ensuring parent records are seeded before their children.
    *   `ExternalOrgQueryService`: Executes remote SOQL against the Source org to fetch data.
    *   `ExternalOrgDmlService`: Pushes records to the Destination org using the Salesforce REST Composite API for bulkified inserts.
    *   `DataSeedingService`: Orchestrates the high-level logic.
*   **Batch Layer:** `DataSeedingBatch` manages the iterative data transfer. It queries source records, maps their old Source IDs to the newly created Destination IDs in-memory (`idRemap`), and inserts them in topological order.

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

## 4. Basic Usage Instructions

1.  **Installation & Setup:** Install the application in a Salesforce org. Add the remote site settings for the orgs you wish to connect to (e.g., login.salesforce.com or test.salesforce.com).
2.  **Authentication:** Open the DBT Data Seeding app. Enter the Username, Password, and Security Token (if applicable) for both the Source Org and the Destination Org.
3.  **Configuration:** Select the root object(s) you wish to seed (e.g., Account, Contact). The application will automatically discover and list required parent objects.
4.  **Execution:** Click the "Execute" or "Start Seeding" button.
5.  **Monitoring:** The LWC UI will poll the batch job status, displaying progress and any errors encountered during the data transfer.

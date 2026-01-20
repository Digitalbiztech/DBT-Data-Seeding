import { LightningElement, track } from "lwc";
import testConnection from "@salesforce/apex/ExternalOrgQueryController.testConnection";
import getAvailableObjects from "@salesforce/apex/ExternalOrgQueryController.getAvailableObjects";
import getObjectDependencies from "@salesforce/apex/ExternalOrgQueryController.getObjectDependencies";
import getCreateableFields from "@salesforce/apex/ExternalOrgQueryController.getCreateableFields";
import queryWithSession from "@salesforce/apex/ExternalOrgQueryController.queryWithSession";
import getAvailableObjectsCurrent from "@salesforce/apex/ExternalOrgQueryController.getAvailableObjectsCurrent";
import getObjectDependenciesCurrent from "@salesforce/apex/ExternalOrgQueryController.getObjectDependenciesCurrent";
import getCreateableFieldsCurrent from "@salesforce/apex/ExternalOrgQueryController.getCreateableFieldsCurrent";
import queryCurrent from "@salesforce/apex/ExternalOrgQueryController.queryCurrent";
import insertRecordsCurrent from "@salesforce/apex/ExternalOrgQueryController.insertRecordsCurrent";
import updateRecordsCurrent from "@salesforce/apex/ExternalOrgQueryController.updateRecordsCurrent";
import createRecordsRemote from "@salesforce/apex/ExternalOrgQueryController.createRecordsRemote";
import updateRecordsRemote from "@salesforce/apex/ExternalOrgQueryController.updateRecordsRemote";
import findMatchingRecords from "@salesforce/apex/ExternalOrgQueryController.findMatchingRecords";
import startDataSeedingBatch from "@salesforce/apex/ExternalOrgQueryController.startDataSeedingBatch";
import getBatchJobStatus from "@salesforce/apex/ExternalOrgQueryController.getBatchJobStatus";
import getBatchReport from "@salesforce/apex/ExternalOrgQueryController.getBatchReport";
import getRequiredFields from "@salesforce/apex/ExternalOrgQueryController.getRequiredFields";

const STANDARD_OBJECT_NAMES = new Set([
  "Account",
  "Contact",
  "Lead",
  "Opportunity",
  "Case",
  "Campaign",
  "Product2",
  "Pricebook2",
  "PricebookEntry",
  "Quote",
  "Contract",
  "Task",
  "Event",
  "Profile",
  "Role",
  "UserRole",
  "Individual",
  "PermissionSet",
  "Group",
  "Queue",
  "Territory",
  "Asset",
  "Solution",
  "Idea",
  "Vote",
  "Attachment",
  "Document",
  "Folder",
  "ContentDocument",
  "ContentVersion",
  "ContentWorkspace",
  "FeedItem",
  "FeedComment",
  "CollaborationGroup",
  "CollaborationGroupMember",
  "WorkOrder",
  "WorkOrderLineItem",
  "ServiceAppointment",
  "ServiceResource",
  "OperatingHours",
  "ServiceTerritory",
  "Location",
  "MaintenancePlan",
  "MaintenanceAsset",
  "ReturnOrder",
  "ReturnOrderLineItem",
  "Shipment",
  "ShipmentItem",
  "ProductItem",
  "InventoryItem",
  "InventoryAdjustment",
  "InventoryAdjustmentItem",
  "InventoryTransfer",
  "InventoryTransferItem",
  "InventoryCount",
  "InventoryCountItem",
  "InventoryCountAdjustment",
  "InventoryCountAdjustmentItem",
  "InventoryCountAdjustmentLine"
]);

export default class ExternalOrgQuery extends LightningElement {
  // UI state for external org connection and query execution
  // Source org (kept as existing fields for compatibility)
  @track username = "ayannbhunia@gmail.com.pdo3"; // for testing, will remove later
  @track password = "Kolkata1234!1fspkhvNFil1geWgHLxoSYeCM"; // for testing, will remove later
  @track environment = "Production";
  @track testMessage;
  @track sessionId;
  @track instanceUrl;

  // Destination org (new, stored separately)
  @track destUsername = "";
  @track destPassword = "";
  @track destEnvironment = "Production";
  @track destTestMessage;
  @track destSessionId;
  @track destInstanceUrl;
  @track soql = "";
  // Removed table results; we no longer build datatable
  @track error;
  @track availableObjects = [];
  @track selectedObject;
  @track dependencyTree;
  @track showObjectPicker = false;
  @track maxDepth;
  @track excludedObjects = [];
  @track planRoot;
  @track planReady = false;
  @track exportLimit = 2;
  @track exportOrder = [];
  @track lastQueriedIdSnapshot;
  @track finalExportQueries = [];
  @track exportStats;
  @track effectiveDepth;

  get displayDepth() {
    if (this.maxDepth === undefined || this.maxDepth === null) {
      return `Unlimited (Actual: ${this.effectiveDepth || 0})`;
    }
    return this.maxDepth;
  }
  // Matching UI (wizard) flags (HTML expects these but logic not implemented here)
  @track showMatchingUI = false;
  @track showMatchingUIWizard = false;
  @track wizard = { isOpen: false, step: "select", objects: [], index: 0 };
  // per-object matching state
  matchingOptionsByObject = new Map(); // object -> [{label,value}]
  selectedMatchingFieldsByObject = new Map(); // object -> [field]
  matchResultsByObject = new Map(); // object -> { sourceRows, matchedRows, unmatchedRows, counts, report }
  @track schemaWarnings = new Map(); // object -> [missing fields]
  @track finalReportRows = [];
  // Import status + reporting (used by template)
  @track importStatus = {
    inProgress: false,
    currentObject: "",
    processedObjects: 0,
    totalObjects: 0,
    successCount: 0,
    errorCount: 0,
    detailedMessages: []
  };
  @track batchJobId;
  @track batchStatus;
  @track batchReportRows = [];
  @track successRows = [];
  @track errorRows = [];

  @track showRawErrorModal = false;
  @track selectedRawError = "";

  handleShowRawError(event) {
    const raw = event.target.dataset.raw;
    try {
      this.selectedRawError = JSON.stringify(JSON.parse(raw), null, 2);
    } catch (e) {
      this.selectedRawError = raw;
    }
    this.showRawErrorModal = true;
  }

  handleCloseRawError() {
    this.showRawErrorModal = false;
    this.selectedRawError = "";
  }

  get isBatchProcessing() {
    return (
      !!this.batchJobId &&
      this.batchStatus !== "Completed" &&
      this.batchStatus !== "Failed" &&
      this.batchStatus !== "Aborted"
    );
  }

  successReportLines = [];
  errorReportLines = [];
  isLoading = false;
  // One-shot flags to suppress onchange after manual deselect click
  _suppressSourceChangeOnce = false;
  _suppressDestChangeOnce = false;

  planEdges = new Map();
  lastQueriedIdSets = new Map();
  // Picklist state for current-org selection
  @track sourceUseCurrent = "no";
  @track destUseCurrent = "no";
  // Lightweight console logger
  debug = (...args) => {
    try {
      console.log("[ExternalOrgQuery]", ...args);
    } catch (e) {
      /* no-op */
    }
  };

  get environmentOptions() {
    // Environment options for login host selection
    return [
      { label: "Production", value: "Production" },
      { label: "Sandbox", value: "Sandbox" }
    ];
  }
  get yesNoOptions() {
    return [
      { label: "Yes", value: "yes" },
      { label: "No", value: "no" }
    ];
  }

  // Connection state + button gating
  get isSourceConnected() {
    return this.isSourceCurrentOrg || !!(this.sessionId && this.instanceUrl);
  }

  get isDestinationConnected() {
    return (
      this.isDestinationCurrentOrg ||
      !!(this.destSessionId && this.destInstanceUrl)
    );
  }

  get isRunDisabled() {
    // Disable until source connected, SOQL present, and object picklist loaded
    return (
      !this.isSourceConnected ||
      !this.soql ||
      !this.showObjectPicker ||
      this.isLoading
    );
  }

  get canTestSource() {
    return !!this.username && !!this.password && !this.isLoading;
  }

  get canTestDestination() {
    return !!this.destUsername && !!this.destPassword && !this.isLoading;
  }

  get objectOptions() {
    return this.availableObjects.map((obj) => ({
      label: obj,
      value: obj
    }));
  }

  @track objectFilter = "";
  @track isSearchFocused = false;
  @track showMoreConfigs = false;

  get filteredObjectOptions() {
    const term = (this.objectFilter || "").toLowerCase();
    let opts = this.objectOptions;
    if (term) {
      opts = opts.filter(
        (o) =>
          (o.label && o.label.toLowerCase().includes(term)) ||
          (o.value && o.value.toLowerCase().includes(term))
      );
    }
    // Sort alphabetically
    return opts.sort((a, b) => a.label.localeCompare(b.label));
  }

  handleObjectFilterChange = (event) => {
    this.objectFilter = event.target.value || "";
  };

  handleObjectInputFocus = () => {
    this.isSearchFocused = true;
  };

  handleObjectInputBlur = () => {
    // Delay hiding to allow click event to register

    // eslint-disable-next-line @lwc/lwc/no-async-operation

    setTimeout(() => {
      this.isSearchFocused = false;
    }, 200);
  };

  handleDropdownMouseDown = (event) => {
    // Prevent focus from leaving the input when clicking inside the dropdown (e.g. on the scrollbar)

    event.preventDefault();
  };

  handleObjectSelect = (event) => {
    const selectedVal = event.currentTarget.dataset.value;
    this.selectedObject = selectedVal;
    this.objectFilter = selectedVal; // Update input to show selected value
    this.dependencyTree = undefined;
    this.isSearchFocused = false;
  };

  get showSearchResults() {
    return this.isSearchFocused && this.filteredObjectOptions.length > 0;
  }

  handleToggleMoreConfigs = () => {
    this.showMoreConfigs = !this.showMoreConfigs;
  };

  get moreConfigsLabel() {
    return this.showMoreConfigs ? "- Less" : "+ More";
  }
  get selectedObjectEmpty() {
    return !this.selectedObject;
  }

  get excludedObjectOptions() {
    return this.availableObjects.map((obj) => ({
      label: obj,
      value: obj
    }));
  }

  get standardObjects() {
    return this.availableObjects.filter((obj) =>
      STANDARD_OBJECT_NAMES.has(obj)
    );
  }

  get customObjects() {
    return this.availableObjects.filter(
      (obj) => !STANDARD_OBJECT_NAMES.has(obj)
    );
  }
  // Simple getter methods for template
  handleUsernameChange = (event) => {
    this.username = event.target.value;
    this.testMessage = undefined;
    this.error = undefined;
    this.clearSourceSession();
    this.resetObjectSelection();
    console.log("Username updated");
  };
  handlePasswordChange = (event) => {
    this.password = event.target.value;
    this.testMessage = undefined;
    this.error = undefined;
    this.clearSourceSession();
    this.resetObjectSelection();
    console.log("Password updated");
  };
  handleEnvironmentChange = (event) => {
    this.environment = event.detail.value;
    this.testMessage = undefined;
    this.error = undefined;
    this.clearSourceSession();
    this.resetObjectSelection();
  };
  handleSoqlChange = (event) => {
    this.soql = event.target.value;
  };
  handleObjectChange = (event) => {
    this.selectedObject = event.detail.value;
    this.dependencyTree = undefined;
  };

  // Destination input handlers
  handleDestUsernameChange = (event) => {
    this.destUsername = event.target.value;
    this.destTestMessage = undefined;
  };
  handleDestPasswordChange = (event) => {
    this.destPassword = event.target.value;
    this.destTestMessage = undefined;
  };
  handleDestEnvironmentChange = (event) => {
    this.destEnvironment = event.detail.value;
    this.destTestMessage = undefined;
  };
  handleDepthChange = (event) => {
    const val = event.target.value;
    if (val === "" || val === null || val === undefined) {
      this.maxDepth = undefined;
    } else {
      const raw = parseInt(val, 10);
      this.maxDepth = Number.isFinite(raw) && raw >= 0 ? raw : undefined;
    }
    this.dependencyTree = undefined;
  }; // New picklist handlers to centralize YES/NO and keep Source/Destination synchronized
  handleSourceCurrentPick = (event) => {
    const val = (event && event.detail && event.detail.value) || "no";
    this.sourceUseCurrent = val;
    if (val === "yes") {
      // Force destination to NO
      this.destUseCurrent = "no";
      this.currentOrgFor = "source";
      this.destTestMessage = undefined;
      // Switch to current-org for source: reset external session/UI and load objects
      this.clearSourceSession();
      this.resetObjectSelection();
      this.fetchAvailableObjectsSource();
    } else {
      // Turning off current org for source
      if (this.isSourceCurrentOrg) {
        this.currentOrgFor = this.destUseCurrent === "yes" ? "destination" : "";
      }
      this.clearSourceSession();
      this.resetObjectSelection();
    }
  };

  handleDestinationCurrentPick = (event) => {
    const val = (event && event.detail && event.detail.value) || "no";
    this.destUseCurrent = val;
    if (val === "yes") {
      // Force source to NO
      this.sourceUseCurrent = "no";
      this.currentOrgFor = "destination";
      // Clear destination external session as we are using current org
      this.destSessionId = undefined;
      this.destInstanceUrl = undefined;
      this.destTestMessage = undefined;
    } else {
      // Turning off current org for destination
      if (this.isDestinationCurrentOrg) {
        this.currentOrgFor = this.sourceUseCurrent === "yes" ? "source" : "";
      }
    }
  };

  // Helper utilities to centralize connection routing
  isSourceCurrent() {
    return this.isSourceCurrentOrg;
  }
  isDestinationCurrent() {
    return this.isDestinationCurrentOrg;
  }
  ensureSourceConnected(message = "Please test connection first") {
    if (this.isSourceCurrentOrg) return true;
    if (this.sessionId && this.instanceUrl) return true;
    this.error = message;
    return false;
  }
  ensureDestinationConnected(message = "Please test connection first") {
    if (this.isDestinationCurrentOrg) return true;
    if (this.destSessionId && this.destInstanceUrl) return true;
    this.error = message;
    return false;
  }
  routeSourceCall(fnCurrent, fnSession) {
    return this.isSourceCurrentOrg ? fnCurrent() : fnSession();
  }
  routeDestinationCall(fnCurrent, fnSession) {
    return this.isDestinationCurrentOrg ? fnCurrent() : fnSession();
  }
  handleExcludedObjectsChange = (event) => {
    this.excludedObjects = event.detail.value || [];
    this.dependencyTree = undefined;
  };
  handleSelectStandardObjects = () => {
    this.excludedObjects = this.standardObjects;
    this.dependencyTree = undefined;
  };
  handleSelectCustomObjects = () => {
    this.excludedObjects = this.customObjects;
    this.dependencyTree = undefined;
  };
  handleClearExclusions = () => {
    this.excludedObjects = [];
    this.dependencyTree = undefined;
  };

  // Current Org selection state
  @track currentOrgFor = "";
  get isSourceCurrentOrg() {
    return this.currentOrgFor === "source";
  }
  get isDestinationCurrentOrg() {
    return this.currentOrgFor === "destination";
  }
  get sourceSectionClass() {
    return this.isSourceCurrentOrg ? "section-disabled" : "";
  }
  get destinationSectionClass() {
    return this.isDestinationCurrentOrg ? "section-disabled" : "";
  }
  handleSelectSourceCurrent = () => {
    if (this._suppressSourceChangeOnce) {
      this._suppressSourceChangeOnce = false;
      return;
    }
    if (!this.isSourceCurrentOrg) {
      this.currentOrgFor = "source";
      this.sourceUseCurrent = "yes";
      this.destUseCurrent = "no";
      this.destTestMessage = undefined;
      // Clear any external source session and fetch current org objects
      this.clearSourceSession();
      this.resetObjectSelection();
      this.fetchAvailableObjectsSource();
    }
  };
  handleSelectDestinationCurrent = () => {
    if (this._suppressDestChangeOnce) {
      this._suppressDestChangeOnce = false;
      return;
    }
    if (!this.isDestinationCurrentOrg) {
      this.currentOrgFor = "destination";
      this.sourceUseCurrent = "no";
      this.destUseCurrent = "yes";
      // Clear destination external session
      this.destSessionId = undefined;
      this.destInstanceUrl = undefined;
      this.destTestMessage = undefined;
    }
  };

  // Allow unselecting the currently selected radio by clicking it again
  handleToggleSourceCurrent = (event) => {
    try {
      event && event.stopPropagation && event.stopPropagation();
    } catch (e) {
      /* no-op */
    }
    if (this.isSourceCurrentOrg) {
      // Suppress the immediate onchange that lightning-input may fire
      this._suppressSourceChangeOnce = true;
      // Unselect current-org for source
      this.currentOrgFor = "";
      // Reset UI that depends on source connection/object list
      this.clearSourceSession();
      this.resetObjectSelection();
    }
    // If not selected, normal onchange will handle selecting it
  };

  handleToggleDestinationCurrent = (event) => {
    try {
      event && event.stopPropagation && event.stopPropagation();
    } catch (e) {
      /* no-op */
    }
    if (this.isDestinationCurrentOrg) {
      // Suppress the immediate onchange that lightning-input may fire
      this._suppressDestChangeOnce = true;
      // Unselect current-org for destination
      this.currentOrgFor = "";
      // No additional cleanup needed for destination beyond UI state
    }
    // If not selected, normal onchange will handle selecting it
  };
  get hasPlan() {
    // Consider a plan valid if we built a root node, even with no edges
    return this.planReady && !!this.planRoot;
  }

  get canShowPlanControls() {
    return this.hasPlan;
  }

  get hasCollectedIds() {
    return (
      this.lastQueriedIdSets &&
      typeof this.lastQueriedIdSets.size === "number" &&
      this.lastQueriedIdSets.size > 0
    );
  }

  get isExportDisabled() {
    return !this.hasPlan || !this.hasExportOrder || this.isLoading;
  }

  get isFinalExportDisabled() {
    const destConnected =
      this.isDestinationCurrentOrg ||
      (!!this.destSessionId && !!this.destInstanceUrl);
    return this.isExportDisabled || !this.hasCollectedIds || !destConnected;
  }

  get hasFinalQueries() {
    return (
      Array.isArray(this.finalExportQueries) &&
      this.finalExportQueries.length > 0
    );
  }

  get isStartImportDisabled() {
    // Support import if Destination is connected (Current or Remote)
    return (
      !this.hasFinalQueries ||
      this.isLoading ||
      !this.isDestinationConnected ||
      this.isBatchProcessing
    );
  }

  // Import UI computed getters
  get importProgressPercentage() {
    if (this.isBatchProcessing && this.importStatus.totalObjects > 0) {
      const p = this.importStatus.processedObjects;
      const t = this.importStatus.totalObjects;
      return Math.floor((Math.min(p, t) / t) * 100);
    }
    const t =
      this.importStatus && this.importStatus.totalObjects
        ? this.importStatus.totalObjects
        : 0;
    const p =
      this.importStatus && this.importStatus.processedObjects
        ? this.importStatus.processedObjects
        : 0;
    if (!t) return 0;
    const pct = Math.floor((Math.min(p, t) / t) * 100);
    return isNaN(pct) ? 0 : pct;
  }
  get importProgressStyle() {
    return `width: ${this.importProgressPercentage}%`;
  }
  get hasImportResults() {
    const s = (this.importStatus && this.importStatus.successCount) || 0;
    const e = (this.importStatus && this.importStatus.errorCount) || 0;
    const finished = !this.importStatus.inProgress && !this.isBatchProcessing;
    return finished && (s + e > 0 || this.batchStatus === "Completed");
  }
  get hasSuccessReport() {
    return this.successReportLines && this.successReportLines.length > 0;
  }
  get hasErrorReport() {
    return this.errorReportLines && this.errorReportLines.length > 0;
  }
  get formattedSuccessReport() {
    return (this.successReportLines || []).join("<br/>");
  }
  get formattedErrorReport() {
    return (this.errorReportLines || []).join("\n");
  }
  get hasBatchReportRows() {
    return this.batchReportRows && this.batchReportRows.length > 0;
  }
  get hasSuccessRows() {
    return this.successRows && this.successRows.length > 0;
  }
  get hasErrorRows() {
    return this.errorRows && this.errorRows.length > 0;
  }

  async handleStartImport() {
    if (!this.hasFinalQueries) {
      this.error = "No final export queries available. Run Final Export first";
      return;
    }
    if (!this.isDestinationConnected) {
      this.error = "Start Import requires a connected Destination";
      return;
    }

    this.error = undefined;
    this.isLoading = true;
    this.batchReportRows = [];
    this.successRows = [];
    this.errorRows = [];

    try {
      // 1. Organize Tasks in Dependency Order (Parents First)
      const groupedQueries = new Map();
      for (const q of this.finalExportQueries) {
        if (!groupedQueries.has(q.objectName))
          groupedQueries.set(q.objectName, []);
        groupedQueries.get(q.objectName).push(q);
      }

      const orderedTasks = [];
      // 'exportOrder' is topologically sorted (Parent -> Child).
      for (const objName of this.exportOrder) {
        if (groupedQueries.has(objName)) {
          orderedTasks.push(...groupedQueries.get(objName));
        }
      }

      // 2. Build Reference Map (Schema for Batch)
      // Transform planEdges (Map<String, Array>) to Map<String, Map<String, String>>
      const referenceMap = {};
      for (const [obj, edges] of this.planEdges.entries()) {
        const fieldMap = {};
        if (Array.isArray(edges)) {
          for (const e of edges) {
            if (e.fieldName && e.target) {
              fieldMap[e.fieldName] = e.target;
            }
          }
        }
        referenceMap[obj] = fieldMap;
      }

      // 3. Start Batch
      const sourceSess = this.isSourceCurrentOrg ? null : this.sessionId;
      const sourceUrl = this.isSourceCurrentOrg ? null : this.instanceUrl;
      const destSess = this.isDestinationCurrentOrg ? null : this.destSessionId;
      const destUrl = this.isDestinationCurrentOrg
        ? null
        : this.destInstanceUrl;

      this.batchJobId = await startDataSeedingBatch({
        sourceSessionId: sourceSess,
        sourceInstanceUrl: sourceUrl,
        destSessionId: destSess,
        destInstanceUrl: destUrl,
        tasks: orderedTasks,
        planEdges: referenceMap
      });

      this.batchStatus = "Queued";
      this.importStatus = {
        inProgress: true,
        currentObject: "Initializing Batch...",
        processedObjects: 0,
        totalObjects: orderedTasks.length, // Track progress by task count
        successCount: 0,
        errorCount: 0,
        detailedMessages: []
      };
      this.successReportLines = [];
      this.errorReportLines = [];

      // Start Polling
      this.pollBatchStatus();
    } catch (e) {
      const msg =
        e && e.body && e.body.message
          ? e.body.message
          : e && e.message
            ? e.message
            : "Batch start failed";
      this.error = msg;
      this.importStatus.inProgress = false;
    } finally {
      this.isLoading = false;
    }
  }

  async pollBatchStatus() {
    if (!this.batchJobId) return;

    try {
      const job = await getBatchJobStatus({ jobId: this.batchJobId });
      if (job) {
        this.batchStatus = job.Status;
        this.importStatus.processedObjects = job.JobItemsProcessed;
        this.importStatus.totalObjects = job.TotalJobItems;
        this.importStatus.errorCount = job.NumberOfErrors;

        const pct =
          job.TotalJobItems > 0
            ? Math.floor((job.JobItemsProcessed / job.TotalJobItems) * 100)
            : 0;
        this.importStatus.currentObject = `Batch ${job.Status} (${pct}%)`;

        if (["Completed", "Failed", "Aborted"].includes(job.Status)) {
          this.importStatus.inProgress = false;
          if (job.Status !== "Completed") {
            this.importStatus.detailedMessages.push(
              `Batch Finished with status: ${job.Status} - ${job.ExtendedStatus || ""}`
            );
          }
          if (job.Status === "Completed") {
            this.successReportLines.push(
              `Batch Completed successfully. Processed ${job.JobItemsProcessed} items.`
            );

            // Fetch detailed report with retries
            let reportJson = null;
            let attempts = 0;
            console.log("Starting report fetch loop for Job:", this.batchJobId);
            while (!reportJson && attempts < 5) {
              try {
                console.log(`Attempt ${attempts + 1} to fetch report...`);
                reportJson = await getBatchReport({ jobId: this.batchJobId });
                console.log(
                  `Attempt ${attempts + 1} result length:`,
                  reportJson ? reportJson.length : "null"
                );
              } catch (err) {
                console.error(
                  "Failed to load batch report attempt " + attempts,
                  err
                );
              }
              if (!reportJson) {
                attempts++;
                console.log("Report not found, waiting 1s...");
                // Wait 1s before retry
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                await new Promise((resolve) => setTimeout(resolve, 1000));
              }
            }

            if (reportJson) {
              try {
                console.log("Parsing report JSON...");
                const rows = JSON.parse(reportJson);
                console.log("Parsed rows count:", rows ? rows.length : 0);
                this.batchReportRows = rows;

                // Separate rows into success and error lists
                this.successRows = rows.filter((r) => r.status === "Success");
                this.errorRows = rows.filter((r) => r.status !== "Success");

                console.log("Success rows:", this.successRows.length);
                console.log("Error rows:", this.errorRows.length);

                this.importStatus.successCount = this.successRows.length;
                this.importStatus.errorCount = this.errorRows.length;
              } catch (parseErr) {
                console.error("Error parsing batch report", parseErr);
                this.errorReportLines.push("Error parsing batch report.");
              }
            } else {
              console.warn("Batch report not found after retries.");
              this.errorReportLines.push(
                "Unable to retrieve batch report details (file not found)."
              );
            }
          } else {
            this.errorReportLines.push(
              `Batch ended with status: ${job.Status}. Errors: ${job.NumberOfErrors}`
            );
          }
          this.batchJobId = undefined; // Stop polling state
        } else {
          // Continue polling
          // eslint-disable-next-line @lwc/lwc/no-async-operation
          setTimeout(() => this.pollBatchStatus(), 2000);
        }
      }
    } catch (e) {
      console.error("Polling error", e);
      this.importStatus.inProgress = false;
    }
  }

  applySoqlConstraints() {
    if (!this.planRoot || !this.soqlConstraints) return;

    const constraints = this.soqlConstraints;
    const requestedRels = new Set(
      (constraints.relationships || []).map((r) => r.toLowerCase())
    );
    const subqueries = new Set(
      (constraints.subqueries || []).map((s) => s.toLowerCase())
    );

    // Helper to uncheck everything first
    const setAll = (node, selected) => {
      if (!node) return;
      if (node.type === "edge") {
        node.isSelected = selected;
        node.lockedByAncestor = !selected;
      } else {
        node.lockedByAncestor = !selected;
      }
      if (node.children) {
        node.children.forEach((c) => setAll(c, selected));
      }
    };

    // If SELECT * or no constraints, select all (default behavior)
    if (!constraints.fields) {
      return;
    }

    // Unselect everything initially
    const root = this.clonePlanNode(this.planRoot);
    setAll(root, false);

    // Traverse and select required paths
    root.lockedByAncestor = false; // Root is active

    const processNode = (node) => {
      if (!node || !node.children) return;

      node.children.forEach((child) => {
        if (child.type === "edge") {
          const relName = (
            child.relationshipName ||
            child.fieldName ||
            ""
          ).toLowerCase();
          const isSubquery =
            child.relationshipType === "Child" && subqueries.has(relName);
          const isRequested = requestedRels.has(relName);

          if (isRequested || isSubquery || child.isRequired) {
            child.isSelected = true;
            child.lockedByAncestor = false;
            if (child.children && child.children[0]) {
              // Unlock the target object
              child.children[0].lockedByAncestor = false;
            }
          }
        }
      });
    };

    processNode(root);

    this.planRoot = root;
    this.effectiveDepth = this.calculateSelectedDepth(this.planRoot);
  }

  handlePlanNodeToggle = (event) => {
    const { nodeId } = event.detail || {};
    if (!nodeId || !this.planRoot) {
      return;
    }
    const clonedRoot = this.clonePlanNode(this.planRoot);
    if (this.toggleNodeCollapsed(clonedRoot, nodeId)) {
      this.planRoot = clonedRoot;
      // Re-calculate effective depth as graph visibility/structure might conceptually change
      // (though strictly speaking, structure is same, we just update it to be safe or if we implement dynamic loading later)
      // For now, static structure means depth doesn't change on toggle, but if we drop nodes it might.
    }
  };

  handlePlanNodeDrop = (event) => {
    const { sourceId, targetId } = event.detail || {};
    if (!sourceId || !targetId || sourceId === targetId || !this.planRoot) {
      return;
    }
    const fromInfo = this.findParentAndIndexById(this.planRoot, sourceId);
    const toInfo = this.findParentAndIndexById(this.planRoot, targetId);
    if (!fromInfo || !toInfo || fromInfo.parent.id !== toInfo.parent.id) {
      return; // only reorder within same parent for now
    }
    const parent = fromInfo.parent;
    const currentChildren = [...parent.children];
    const [moved] = currentChildren.splice(fromInfo.index, 1);
    currentChildren.splice(toInfo.index, 0, moved);
    parent.children = currentChildren;
    this.planRoot = this.clonePlanNode(this.planRoot);
    // Recalculate depth after structure change
    this.effectiveDepth = this.calculateSelectedDepth(this.planRoot);
    if (parent.id === "plan-root") {
      this.exportOrder = currentChildren.map((node) =>
        node.type === "edge" && node.targetObject
          ? node.targetObject
          : node.objectName || node.label
      );
      console.log(
        JSON.stringify(
          { type: "PLAN_REORDER", order: this.exportOrder },
          null,
          2
        )
      );
    }
  };
  clonePlanNode(node) {
    if (!node) {
      return node;
    }
    return {
      ...node,
      children: node.children
        ? node.children.map((child) => this.clonePlanNode(child))
        : []
    };
  }

  handleExpandAll = () => {
    if (!this.planRoot) return;
    const clone = this.clonePlanNode(this.planRoot);
    const setCollapsed = (node, collapsed) => {
      if (!node) return;
      if (node.children && node.children.length) {
        node.isCollapsed = collapsed;
        for (const child of node.children) setCollapsed(child, collapsed);
      }
    };
    setCollapsed(clone, false);
    this.planRoot = clone;
  };

  handleCollapseAll = () => {
    if (!this.planRoot) return;
    const clone = this.clonePlanNode(this.planRoot);
    const setCollapsed = (node, collapsed) => {
      if (!node) return;
      if (node.children && node.children.length) {
        node.isCollapsed = collapsed;
        for (const child of node.children) setCollapsed(child, collapsed);
      }
    };
    setCollapsed(clone, true);
    this.planRoot = clone;
  };

  toggleNodeCollapsed(node, nodeId) {
    if (!node) {
      return false;
    }
    if (node.id === nodeId) {
      node.isCollapsed = !node.isCollapsed;
      // If expanding an edge node with a suppressed child object header,
      // also uncollapse the immediate child object so grandchildren become visible.
      if (
        !node.isCollapsed &&
        node.type === "edge" &&
        node.children &&
        node.children[0]
      ) {
        node.children[0].isCollapsed = false;
      }
      return true;
    }
    if (node.children && node.children.length) {
      for (const child of node.children) {
        if (this.toggleNodeCollapsed(child, nodeId)) {
          return true;
        }
      }
    }
    return false;
  }

  calculateDepth(node, currentDepth = 0) {
    if (!node) return currentDepth;
    let max = currentDepth;
    if (node.children && node.children.length > 0) {
      for (const child of node.children) {
        // If child is an edge, it increases depth for the target object
        // If child is object, it represents that next level
        const nextDepth =
          child.type === "edge" ? currentDepth + 1 : currentDepth;
        const d = this.calculateDepth(child, nextDepth);
        if (d > max) max = d;
      }
    }
    return max;
  }

  buildPlanState(dependencyTree) {
    if (!dependencyTree) {
      this.planRoot = undefined;
      this.planEdges = new Map();
      this.exportOrder = [];
      this.planReady = false;
      return;
    }
    const edgesByObject = this.collectPlanEdges(dependencyTree);
    const rootObject = dependencyTree.objectName;
    const order = this.computeExportOrder(edgesByObject, rootObject);
    this.exportOrder = order;
    this.planEdges = edgesByObject;
    this.planRoot = this.buildPlanTree(rootObject, order, edgesByObject);
    // Calculate effective depth from graph (initially all selected)
    const computedDepth = this.calculateSelectedDepth(this.planRoot);
    this.effectiveDepth = computedDepth;
    this.planReady = true;
    this.lastQueriedIdSets = new Map();
    this.lastQueriedIdSnapshot = undefined;
    this.exportStats = undefined;
    this.effectiveDepth = undefined;
    return;
  }
  collectPlanEdges(root) {
    const edgesByObject = new Map();
    const visitedEdges = new Set();
    const addEdge = (fromObj, fieldName, toObj, relName, type, isRequired) => {
      if (!fromObj || !fieldName || !toObj) {
        return;
      }
      if (!edgesByObject.has(fromObj)) {
        edgesByObject.set(fromObj, []);
      }
      const existing = edgesByObject.get(fromObj);
      // Use composite key to avoid duplicates? Or simply check if already added
      if (
        !existing.some(
          (edge) => edge.fieldName === fieldName && edge.target === toObj
        )
      ) {
        existing.push({
          fieldName,
          target: toObj,
          relationshipName: relName,
          relationshipType: type,
          isRequired
        });
      }
    };

    const walkParents = (currentObjectName, parents, path = new Set()) => {
      if (!parents || !parents.length) {
        return;
      }
      const nextPath = new Set(path);
      if (currentObjectName) {
        nextPath.add(currentObjectName);
      }
      for (const parent of parents) {
        const edgeKey = `${currentObjectName}|${parent.fieldName}|${parent.objectName}`;
        if (!visitedEdges.has(edgeKey)) {
          addEdge(
            currentObjectName,
            parent.fieldName,
            parent.objectName,
            parent.relationshipName,
            parent.relationshipType,
            parent.isRequired
          );
          visitedEdges.add(edgeKey);
        }
        if (parent.objectName && !nextPath.has(parent.objectName)) {
          walkParents(parent.objectName, parent.parents, nextPath);
        }
      }
    };

    if (root && root.objectName) {
      // Also collect child relationships from root.children if present
      if (root.children) {
        // We treat child relationships as edges from Root -> Child
        root.children.forEach((child) => {
          const edgeKey = `${root.objectName}|${child.fieldName}|${child.objectName}`;
          if (!visitedEdges.has(edgeKey)) {
            addEdge(
              root.objectName,
              child.fieldName,
              child.objectName,
              child.relationshipName,
              "Child",
              false
            );
            visitedEdges.add(edgeKey);
          }
        });
      }
      walkParents(root.objectName, root.parents || []);
    }

    const visitedObjects = new Set();
    const collectObjects = (node) => {
      if (!node || !node.objectName || visitedObjects.has(node.objectName)) {
        return;
      }
      visitedObjects.add(node.objectName);
      if (!edgesByObject.has(node.objectName)) {
        edgesByObject.set(node.objectName, []);
      }
      // Collect children edges here too for deep traversal?
      // The original logic only traversed `parents` which are Lookups.
      // Child relationships (downwards) were only at the root level in the Apex tree?
      // Apex `buildDependencyTree` returns a root with `children` (child relationships).
      // But it doesn't recurse down children unless we implement full graph traversal.
      // Currently `collectObjects` recursively visits `parents`.

      // If the node has children (Child Relationships), add them as edges
      if (node.children) {
        node.children.forEach((child) => {
          // Only add if not already visited?
          const edgeKey = `${node.objectName}|${child.fieldName}|${child.objectName}`;
          if (!visitedEdges.has(edgeKey)) {
            addEdge(
              node.objectName,
              child.fieldName,
              child.objectName,
              child.relationshipName,
              "Child",
              false
            );
            visitedEdges.add(edgeKey);
          }
        });
      }

      (node.parents || []).forEach(collectObjects);
    };
    collectObjects(root);

    return edgesByObject;
  }
  buildPlanTree(rootObject, order, edgesByObject) {
    const buildEdgeNode = (fromObj, edge, pathKey, depth, visited, seq) => {
      const edgeId = `edge-${pathKey}-${fromObj}-${edge.fieldName}-${edge.target}`;
      const childObjectNode = buildObjectNode(
        edge.target,
        `${pathKey}o`,
        depth + 1,
        visited
      );
      if (childObjectNode) {
        childObjectNode.suppressHeader = true;
        childObjectNode.isCollapsed = false;
      }
      return {
        id: edgeId,
        type: "edge",
        label: `${edge.relationshipName || edge.fieldName} -> ${edge.target}`, // Use relationship name if avail
        objectName: fromObj,
        fieldName: edge.fieldName,
        relationshipName: edge.relationshipName,
        relationshipType: edge.relationshipType,
        isRequired: edge.isRequired,
        targetObject: edge.target,
        isCollapsed: false,
        isLeaf: false,
        draggable: true,
        isSelected: true,
        seq,
        children: childObjectNode ? [childObjectNode] : []
      };
    };

    const buildObjectNode = (
      objectName,
      pathKey = "r",
      depth = 0,
      visited = new Set()
    ) => {
      const nodeId = `obj-${pathKey}-${objectName}`;
      const node = {
        id: nodeId,
        type: "object",
        label: objectName,
        objectName,
        isCollapsed: depth > 0,
        isLeaf: false,
        draggable: true,
        children: []
      };
      // Prevent cycles: if this object is already in the current path, stop here
      if (visited.has(objectName)) {
        node.isLeaf = true;
        return node;
      }
      const nextVisited = new Set(visited);
      nextVisited.add(objectName);
      const edges = edgesByObject.get(objectName) || [];
      edges.forEach((e, idx) => {
        const edgeNode = buildEdgeNode(
          objectName,
          e,
          `${pathKey}e${idx}`,
          depth + 1,
          nextVisited,
          idx + 1
        );
        node.children.push(edgeNode);
      });
      node.isLeaf = node.children.length === 0;
      return node;
    };

    const root = buildObjectNode(rootObject, "r", 0, new Set());
    root.draggable = false;
    root.label = `Export Plan for ${rootObject}`;
    root.id = "plan-root";
    return root;
  }
  findParentAndIndexById(node, id) {
    if (!node || !id) return null;
    const stack = [node];
    while (stack.length) {
      const current = stack.pop();
      if (!current || !current.children) continue;
      for (let i = 0; i < current.children.length; i++) {
        const child = current.children[i];
        if (child && child.id === id) {
          return { parent: current, index: i };
        }
        stack.push(child);
      }
    }
    return null;
  }

  @track soqlConstraints;

  async handleRunQuery() {
    this.error = undefined;
    this.testMessage = undefined;
    this.debug("Run Query clicked", {
      isSourceConnected: this.isSourceConnected,
      showObjectPicker: this.showObjectPicker,
      isLoading: this.isLoading,
      soqlPreview: (this.soql || "").slice(0, 120)
    });
    if (!this.isSourceConnected) {
      this.error = "Please test Source connection first";
      this.debug("Blocked: source not connected");
      return;
    }

    try {
      const parsed = this.parseSoql(this.soql || "");
      if (parsed && parsed.objectName) {
        const obj = parsed.objectName;
        const match = this.findAvailableObjectMatch(obj);
        if (match) {
          this.selectedObject = match;
          // Preserve constraints for plan generation
          this.soqlConstraints = parsed;

          if (Number.isFinite(parsed.limit)) {
            this.exportLimit = parsed.limit;
          }

          // Automatically trigger plan check
          this.debug("Auto-triggering Check Plan for:", this.selectedObject);
          // Use a small delay to allow UI to update selectedObject if needed, though track should handle it
          // Directly calling handleCheckPlan
          await this.handleCheckPlan(true); // pass true for auto-apply
        } else {
          const msg = `Object "${obj}" not found in available objects`;
          this.error = msg;
          this.debug("SOQL object match error:", msg);
        }
      }
    } catch (parseErr) {
      this.error =
        parseErr && parseErr.message
          ? parseErr.message
          : "Failed to parse SOQL";
    }
  }

  parseSoql(soql) {
    const text = (soql || "").trim();
    if (!text) throw new Error("SOQL is empty");

    let balance = 0;
    let fromIndex = -1;
    const upper = text.toUpperCase();

    for (let i = 0; i < upper.length; i++) {
      const char = upper[i];
      if (char === "(") balance++;
      else if (char === ")") balance--;

      if (balance === 0 && upper.substring(i).startsWith("FROM")) {
        const afterFrom = upper[i + 4];
        // Check if FROM is a whole word (followed by whitespace or EOF)
        if (!afterFrom || /\s/.test(afterFrom)) {
          fromIndex = i;
          break;
        }
      }
    }

    if (fromIndex === -1)
      throw new Error("Unable to find top-level FROM clause");

    const selectPart = text.substring(6, fromIndex).trim();
    const restPart = text.substring(fromIndex + 4).trim(); // Skip 'FROM' (4 chars)

    const objectMatch = restPart.match(/^([a-zA-Z0-9_]+)/);
    if (!objectMatch) throw new Error("Unable to parse object name");
    const objectName = objectMatch[1];

    let limitVal;
    const limitMatch = restPart.match(/\bLIMIT\s+(\d+)/i);
    if (limitMatch) {
      limitVal = parseInt(limitMatch[1], 10);
    }

    const fields = [];
    const subqueries = [];
    const relationships = new Set();

    let currentToken = "";
    balance = 0;
    for (let i = 0; i < selectPart.length; i++) {
      const c = selectPart[i];
      if (c === "(") balance++;
      if (c === ")") balance--;

      if (c === "," && balance === 0) {
        this.processSelectToken(
          currentToken.trim(),
          fields,
          subqueries,
          relationships
        );
        currentToken = "";
      } else {
        currentToken += c;
      }
    }
    if (currentToken.trim()) {
      this.processSelectToken(
        currentToken.trim(),
        fields,
        subqueries,
        relationships
      );
    }

    const isWildcard = fields.some((f) => f === "*");

    return {
      objectName,
      limit: limitVal,
      fields: isWildcard ? null : fields,
      subqueries,
      relationships: isWildcard ? null : Array.from(relationships)
    };
  }

  processSelectToken(token, fields, subqueries, relationships) {
    if (!token) return;

    // Check for subquery
    if (token.toUpperCase().startsWith("(SELECT")) {
      // Extract FROM in subquery
      const match = token.match(/\bFROM\s+([a-zA-Z0-9_]+)/i);
      if (match) {
        const rel = match[1];
        subqueries.push(rel);
        relationships.add(rel);
      }
    } else {
      // Standard field
      fields.push(token);
      // Check for Parent.Field
      if (token.includes(".")) {
        const parts = token.split(".");
        // Add all prefixes as required relationships (e.g. Account.Owner.Name -> Account, Account.Owner)
        // Simply taking the first part usually works for immediate parent
        relationships.add(parts[0]);
      }
    }
  }

  stripNamespace(name) {
    const n = (name || "").trim();
    // Remove leading package namespace prefix like ns__
    return n.replace(/^[a-zA-Z0-9]+__/, "");
  }

  normalizeName(name) {
    return (name || "").toLowerCase();
  }

  findAvailableObjectMatch(objName) {
    const list = Array.isArray(this.availableObjects)
      ? this.availableObjects
      : [];
    const objLower = this.normalizeName(objName);
    // 1) direct case-insensitive match
    const direct = list.find((o) => this.normalizeName(o) === objLower);
    if (direct) return direct;
    // 2) suffix exact match (case-insensitive)
    const suffix = this.normalizeName(this.stripNamespace(objName));
    const exactSuffix = list.find((o) => this.normalizeName(o) === suffix);
    if (exactSuffix) return exactSuffix;
    // 3) namespaced mapping by comparing stripped names case-insensitively
    const candidates = list.filter(
      (o) => this.normalizeName(this.stripNamespace(o)) === suffix
    );
    if (candidates.length === 1) return candidates[0];
    // ambiguous or none => no match
    return null;
  }

  async handleTestConnection() {
    this.error = undefined;
    this.testMessage = undefined;
    this.isLoading = true;
    try {
      this.debug("Calling Apex testConnection (source)", {
        username: this.username,
        environment: this.environment
      });
      const res = await testConnection({
        username: this.username,
        password: this.password,
        environment: this.environment
      });
      if (res && res.success) {
        const instance = res.instanceUrl ? ` (${res.instanceUrl})` : "";
        this.testMessage = `Connection successful${instance}`;

        // Store session details for future API calls
        this.sessionId = res.sessionId;
        this.instanceUrl = res.instanceUrl;

        // Automatically fetch available objects
        await this.fetchAvailableObjectsSource();

        this.debug("Connection test successful (source)");
      } else {
        this.error = res && res.message ? res.message : "Connection failed";
        this.debug("Connection test failed (source)", this.error);
      }
    } catch (e) {
      this.error =
        e && e.body && e.body.message
          ? e.body.message
          : e && e.message
            ? e.message
            : "Unknown error";
      this.debug("Connection test error (source)", this.error);
    } finally {
      this.isLoading = false;
    }
  }
  async handleTestConnectionDestination() {
    // Destination connection test: only display result, store separately
    this.destTestMessage = undefined;
    const credsMissing = !this.destUsername || !this.destPassword;
    if (credsMissing) {
      this.destTestMessage = "Please provide Destination Username and Password";
      return;
    }
    this.isLoading = true;
    try {
      this.debug("Calling Apex testConnection (destination)", {
        username: this.destUsername,
        environment: this.destEnvironment
      });
      const res = await testConnection({
        username: this.destUsername,
        password: this.destPassword,
        environment: this.destEnvironment
      });
      if (res && res.success) {
        const instance = res.instanceUrl ? ` (${res.instanceUrl})` : "";
        this.destTestMessage = `Connection successful${instance}`;
        this.destSessionId = res.sessionId;
        this.destInstanceUrl = res.instanceUrl;
      } else {
        this.destTestMessage =
          res && res.message
            ? `Connection failed: ${res.message}`
            : "Connection failed";
      }
    } catch (e) {
      const msg =
        e && e.body && e.body.message
          ? e.body.message
          : e && e.message
            ? e.message
            : "Unknown error";
      this.destTestMessage = `Connection failed: ${msg}`;
    } finally {
      this.isLoading = false;
    }
  }

  // Unified object list fetch using current-org or session based on source mode
  async fetchAvailableObjectsSource() {
    try {
      this.debug("Fetching available objects (source, routed)");
      const objects = await this.routeSourceCall(
        () => getAvailableObjectsCurrent(),
        () => {
          if (!this.sessionId || !this.instanceUrl) {
            this.debug("No session available for external object fetch");
            return [];
          }
          return getAvailableObjects({
            sessionId: this.sessionId,
            instanceUrl: this.instanceUrl
          });
        }
      );
      this.availableObjects = objects || [];
      this.showObjectPicker = true;
      try {
        this.excludedObjects = this.standardObjects;
      } catch (e) {
        /* no-op */
      }
      this.debug(
        "Fetched objects count",
        (this.availableObjects && this.availableObjects.length) || 0
      );
    } catch (e) {
      this.error =
        e && e.body && e.body.message
          ? e.body.message
          : e && e.message
            ? e.message
            : "Failed to fetch objects";
      this.debug("Error fetching objects", this.error);
    }
  }

  handleLimitChange = (event) => {
    const val = parseInt(event.target.value, 10);
    this.exportLimit = Number.isFinite(val) && val > 0 ? val : 1;
  };

  async runQueryWithSession(soql) {
    return this.routeSourceCall(
      () => queryCurrent({ soql }),
      () =>
        queryWithSession({
          sessionId: this.sessionId,
          instanceUrl: this.instanceUrl,
          soql
        })
    );
  }

  get hasExportOrder() {
    return Array.isArray(this.exportOrder) && this.exportOrder.length > 0;
  }

  async handleExport() {
    if (!this.ensureSourceConnected("Please test connection first")) {
      return;
    }
    if (!this.hasPlan || !this.hasExportOrder) {
      this.error = "Run Check Plan to build the export plan first";
      return;
    }

    const limit =
      Number.isFinite(this.exportLimit) && this.exportLimit > 0
        ? this.exportLimit
        : 1;
    const order = [...this.exportOrder];
    if (!order.length) {
      this.error = "No objects available in export order";
      return;
    }

    this.error = undefined;
    try {
      this.isLoading = true;
      const selectedEdges = this.collectSelectedEdgesFromPlan(this.planRoot);
      const queriedMap = await this.collectIds(order, limit, selectedEdges);
      const cloned = new Map();
      for (const [objectName, idSet] of queriedMap.entries()) {
        cloned.set(objectName, new Set(idSet));
      }
      this.lastQueriedIdSets = cloned;
      this.lastQueriedIdSnapshot = this.serializeIdSets(cloned);

      // Calculate Stats
      let totalRecords = 0;
      let objectCount = 0;
      for (const idSet of cloned.values()) {
        if (idSet && idSet.size > 0) {
          objectCount++;
          totalRecords += idSet.size;
        }
      }
      this.exportStats = { objectCount, totalRecords };
      // Recalculate depth just in case (though graph didn't change, confirms consistency)
      this.effectiveDepth = this.calculateSelectedDepth(this.planRoot);

      console.log(
        JSON.stringify(
          {
            type: "ID_COLLECTION_RESULT",
            queriedIdSet: this.lastQueriedIdSnapshot
          },
          null,
          2
        )
      );
    } catch (e) {
      const msg =
        e && e.body && e.body.message
          ? e.body.message
          : e && e.message
            ? e.message
            : "Export failed";
      this.error = msg;
      console.error("Export error", msg);
    } finally {
      this.isLoading = false;
    }
  }
  handlePlanEdgeToggle = (event) => {
    const { nodeId, isSelected } = event.detail || {};
    if (!nodeId) return;
    const root = this.clonePlanNode(this.planRoot);
    const info = this.findParentAndIndexById(root, nodeId);
    if (!info) return;
    const edgeNode = info.parent.children[info.index];
    edgeNode.isSelected = !!isSelected;
    // Cascade selection + lock state down to all descendant edges below the target object
    const setDescendants = (node, selected) => {
      if (!node || !Array.isArray(node.children)) return;
      for (const child of node.children) {
        if (child.type === "edge") {
          child.isSelected = !!selected;
          child.lockedByAncestor = !selected;
          if (child.children && child.children[0]) {
            child.children[0].lockedByAncestor = !selected;
            setDescendants(child.children[0], selected);
          }
        } else {
          child.lockedByAncestor = !selected;
          setDescendants(child, selected);
        }
      }
    };
    if (edgeNode.children && edgeNode.children[0]) {
      edgeNode.children[0].lockedByAncestor = !isSelected;
      setDescendants(edgeNode.children[0], !!isSelected);
    }
    this.planRoot = root;
    // Recalculate depth based on selected nodes only?
    // Current calculateDepth traverses all children. If we want "selected depth", we need to update calculateDepth.
    // For now, let's keep it as "Graph Depth". If user deselects, the graph structure still exists.
    // But if requirement is "active export depth", we should update calculateDepth to check isSelected.
    this.effectiveDepth = this.calculateSelectedDepth(this.planRoot);
  };

  calculateSelectedDepth(node, currentDepth = 0) {
    if (!node) return currentDepth;
    // If node is not selected (and it's an edge/object that can be deselected), stop?
    // Objects don't have isSelected, Edges do.
    if (node.type === "edge" && !node.isSelected) return currentDepth;

    let max = currentDepth;
    if (node.children && node.children.length > 0) {
      for (const child of node.children) {
        const nextDepth =
          child.type === "edge" ? currentDepth + 1 : currentDepth;
        const d = this.calculateSelectedDepth(child, nextDepth);
        if (d > max) max = d;
      }
    }
    return max;
  }

  // Matching wizard: getters
  get isMatchingStepSelect() {
    return this.showMatchingUIWizard && this.wizard.step === "select";
  }
  get isMatchingStepResults() {
    return this.showMatchingUIWizard && this.wizard.step === "results";
  }
  get isMatchingStepReport() {
    return this.showMatchingUIWizard && this.wizard.step === "report";
  }
  get isMatchingStepSummary() {
    return this.showMatchingUIWizard && this.wizard.step === "summary";
  }
  get currentWizardObject() {
    return this.wizard.objects[this.wizard.index] || "";
  }
  get currentSchemaWarnings() {
    return this.schemaWarnings.get(this.currentWizardObject) || [];
  }
  get hasSchemaWarnings() {
    return this.currentSchemaWarnings.length > 0;
  }
  get currentMatchingObject() {
    return { objectName: this.currentWizardObject };
  }
  get wizardProgressText() {
    const i = this.wizard.index + 1;
    const n = this.wizard.objects.length || 0;
    return `${i} of ${n}`;
  }
  get totalWizardObjectCount() {
    return this.wizard.objects.length || 0;
  }
  get processedObjectCount() {
    return Array.from(this.matchResultsByObject.values()).filter(
      (v) => v && v.report
    ).length;
  }

  // Field options + selections
  get currentFieldOptions() {
    return this.matchingOptionsByObject.get(this.currentWizardObject) || [];
  }
  get currentSelectedFields() {
    return (
      this.selectedMatchingFieldsByObject.get(this.currentWizardObject) || []
    );
  }
  // Legacy UI proxies
  get matchingFieldsOptions() {
    return this.currentFieldOptions;
  }
  get selectedMatchingFields() {
    return this.currentSelectedFields;
  }

  // Result helpers
  get currentResult() {
    return (
      this.matchResultsByObject.get(this.currentWizardObject) || {
        counts: { sourceCount: 0, destCount: 0, matchedCount: 0 },
        unmatchedRows: [],
        matchedRows: [],
        sourceRows: []
      }
    );
  }
  get currentCounts() {
    return this.currentResult.counts;
  }
  get currentUnmatchedCount() {
    return (this.currentResult.unmatchedRows || []).length;
  }
  get hasUnmatchedForCurrent() {
    return this.currentUnmatchedCount > 0;
  }
  get currentReport() {
    return (this.currentResult && this.currentResult.report) || null;
  }
  get hasFinalReport() {
    return (
      Array.isArray(this.finalReportRows) && this.finalReportRows.length > 0
    );
  }
  get currentImportButtonLabel() {
    return "Import Unmatched";
  }
  get nextButtonLabel() {
    return this.wizard.index >= this.wizard.objects.length - 1
      ? "Finish"
      : "Next";
  }
  get isMatchingCheckDisabled() {
    const fields = this.currentSelectedFields;
    return (
      !this.isDestinationConnected ||
      this.isLoading ||
      !(fields && fields.length)
    );
  }
  get isMatchingImportDisabled() {
    return (
      !this.isDestinationConnected ||
      this.isLoading ||
      !this.hasUnmatchedForCurrent
    );
  }

  // Matching wizard: handlers
  handleOpenCheckImport = async () => {
    if (!this.hasFinalQueries) {
      this.error = "Run Final Export first";
      return;
    }
    if (!this.isDestinationConnected) {
      this.error = "Check & Import requires a connected Destination";
      return;
    }
    this.error = undefined;
    // Build unique object list from finalExportQueries
    const objects = Array.from(
      new Set(
        (this.finalExportQueries || [])
          .map((q) => q && q.objectName)
          .filter(Boolean)
      )
    );
    this.wizard = { isOpen: true, step: "select", objects, index: 0 };
    this.showMatchingUIWizard = true;
    // Preload options for first object
    await this.loadMatchingFieldOptionsFor(this.currentWizardObject);
  };

  handleMatchingCancel = () => {
    this.showMatchingUIWizard = false;
    this.wizard = { isOpen: false, step: "select", objects: [], index: 0 };
  };

  handleMatchingFieldChangeForObject = (event) => {
    const values = (event && event.detail && event.detail.value) || [];
    this.selectedMatchingFieldsByObject.set(
      this.currentWizardObject,
      Array.isArray(values) ? values : []
    );
    // Force reactivity
    this.selectedMatchingFieldsByObject = new Map(
      this.selectedMatchingFieldsByObject
    );
  };
  handleMatchingFieldChange = this.handleMatchingFieldChangeForObject;

  handleMatchingDeselectAll = () => {
    this.selectedMatchingFieldsByObject.set(this.currentWizardObject, []);
    this.selectedMatchingFieldsByObject = new Map(
      this.selectedMatchingFieldsByObject
    );
  };
  handleMatchingSelectAll = () => {
    const opts = this.currentFieldOptions;
    this.selectedMatchingFieldsByObject.set(
      this.currentWizardObject,
      opts.map((o) => o.value)
    );
    this.selectedMatchingFieldsByObject = new Map(
      this.selectedMatchingFieldsByObject
    );
  };

  handleRunMatchingCheck = async () => {
    const objectName = this.currentWizardObject;
    const fields = this.currentSelectedFields;
    if (!objectName || !fields || !fields.length) {
      this.error = "Select at least one field to match";
      return;
    }
    this.isLoading = true;
    this.error = undefined;
    try {
      // Gather source rows using finalExportQueries for this object (cap for performance)
      const defs = (this.finalExportQueries || []).filter(
        (d) => d && d.objectName === objectName
      );
      const MAX_ROWS = 2000;
      const sourceRows = [];
      for (const def of defs) {
        if (sourceRows.length >= MAX_ROWS) break;
        const res = await this.runQueryWithSession(def.soql);
        const rows = (res && res.rows) || [];
        for (const r of rows) {
          sourceRows.push(r);
          if (sourceRows.length >= MAX_ROWS) break;
        }
        if (sourceRows.length >= MAX_ROWS) break;
      }

      // Bulk Match via Apex
      // Process in chunks to avoid Apex heap/string limits on the input list
      const BATCH_SIZE = 200;
      const destIdBySourceId = new Map();

      for (let i = 0; i < sourceRows.length; i += BATCH_SIZE) {
        const chunk = sourceRows.slice(i, i + BATCH_SIZE);

        // Determine destination connection details
        // If Current Org, pass nulls to signal local query
        const sess = this.isDestinationCurrentOrg ? null : this.destSessionId;
        const url = this.isDestinationCurrentOrg ? null : this.destInstanceUrl;

        const results = await findMatchingRecords({
          sessionId: sess,
          instanceUrl: url,
          objectName: objectName,
          matchFields: fields,
          sourceRecords: chunk
        });

        if (Array.isArray(results)) {
          for (const m of results) {
            if (m && m.sourceId && m.destId) {
              destIdBySourceId.set(m.sourceId, m.destId);
            }
          }
        }
      }

      // Separate matched vs unmatched
      const matchedRows = [];
      const unmatchedRows = [];
      let matchedCount = 0;

      for (const row of sourceRows) {
        if (!row) continue;
        const srcId = row.Id;
        if (destIdBySourceId.has(srcId)) {
          matchedRows.push({
            source: row,
            dest: { Id: destIdBySourceId.get(srcId) }
          });
          matchedCount++;
        } else {
          unmatchedRows.push(row);
        }
      }

      const counts = {
        sourceCount: sourceRows.length,
        destCount: matchedCount,
        matchedCount
      };
      this.matchResultsByObject.set(objectName, {
        sourceRows,
        matchedRows,
        unmatchedRows,
        counts
      });
      this.matchResultsByObject = new Map(this.matchResultsByObject);
      this.wizard = { ...this.wizard, step: "results" };
    } catch (e) {
      const msg =
        e && e.body && e.body.message
          ? e.body.message
          : e && e.message
            ? e.message
            : "Matching check failed";
      this.error = msg;
    } finally {
      this.isLoading = false;
    }
  };

  handleMatchingImport = async () => {
    const objectName = this.currentWizardObject;
    const res = this.matchResultsByObject.get(objectName);
    const unmatched = (res && res.unmatchedRows) || [];
    if (!objectName || !unmatched.length) return;
    this.isLoading = true;
    try {
      const records = [];
      for (const row of unmatched) {
        const out = { Id: row.Id };
        for (const key of Object.keys(row)) {
          if (key === "Id") continue;
          out[key] = row[key];
        }
        records.push(out);
      }
      const results = await this.routeDestinationCall(
        () => insertRecordsCurrent({ objectName, records }),
        () =>
          createRecordsRemote({
            sessionId: this.destSessionId,
            instanceUrl: this.destInstanceUrl,
            objectName,
            records
          })
      );
      const report = {
        successCount: 0,
        errorCount: 0,
        successes: [],
        errors: []
      };
      const sourceBaseUrl = this.isSourceCurrentOrg
        ? window.location.origin
        : this.instanceUrl;

      if (Array.isArray(results)) {
        for (const r of results) {
          if (r && r.success) {
            report.successCount += 1;
            report.successes.push({
              oldId: r.oldId,
              newId: r.newId,
              name: r.name,
              recordUrl: r.recordUrl
            });
          } else {
            report.errorCount += 1;
            report.errors.push({
              oldId: (r && r.oldId) || "",
              errorMessage: (r && r.errorMessage) || "Unknown error",
              rawError: (r && r.rawError) || null,
              sourceUrl:
                sourceBaseUrl && r.oldId ? `${sourceBaseUrl}/${r.oldId}` : null
            });
          }
        }
      }
      // Save report and update counts
      const counts = res.counts || {
        sourceCount: unmatched.length,
        destCount: 0,
        matchedCount: 0
      };
      // After import, consider newly inserted as matched
      counts.destCount = counts.matchedCount + report.successCount;
      counts.matchedCount = counts.destCount;
      this.matchResultsByObject.set(objectName, { ...res, report, counts });
      this.matchResultsByObject = new Map(this.matchResultsByObject);
      this.wizard = { ...this.wizard, step: "report" };
    } catch (e) {
      this.error =
        e && e.body && e.body.message
          ? e.body.message
          : e && e.message
            ? e.message
            : "Import failed";
    } finally {
      this.isLoading = false;
    }
  };

  get isFirstObject() {
    return this.wizard.index === 0;
  }

  get isMatchingUpsertDisabled() {
    return (
      !this.isDestinationCurrentOrg ||
      this.isLoading ||
      (!this.hasUnmatchedForCurrent &&
        (!this.currentResult.matchedRows ||
          !this.currentResult.matchedRows.length))
    );
  }

  handleMatchingUpsert = async () => {
    const objectName = this.currentWizardObject;
    const res = this.matchResultsByObject.get(objectName);
    const unmatched = (res && res.unmatchedRows) || [];
    const matched = (res && res.matchedRows) || [];

    if (!objectName || (!unmatched.length && !matched.length)) return;

    this.isLoading = true;
    try {
      const report = {
        successCount: 0,
        errorCount: 0,
        successes: [],
        errors: []
      };

      // 1. Insert Unmatched
      if (unmatched.length > 0) {
        const records = unmatched.map((row) => {
          const out = { Id: row.Id };
          for (const key of Object.keys(row)) {
            if (key === "Id") continue;
            out[key] = row[key];
          }
          return out;
        });

        const results = await this.routeDestinationCall(
          () => insertRecordsCurrent({ objectName, records }),
          () =>
            createRecordsRemote({
              sessionId: this.destSessionId,
              instanceUrl: this.destInstanceUrl,
              objectName,
              records
            })
        );

        const sourceBaseUrl = this.isSourceCurrentOrg
          ? window.location.origin
          : this.instanceUrl;

        if (Array.isArray(results)) {
          for (const r of results) {
            if (r && r.success) {
              report.successCount += 1;
              report.successes.push({
                oldId: r.oldId,
                newId: r.newId,
                type: "Insert",
                name: r.name,
                recordUrl: r.recordUrl
              });
            } else {
              report.errorCount += 1;
              report.errors.push({
                oldId: (r && r.oldId) || "",
                errorMessage: (r && r.errorMessage) || "Unknown error",
                rawError: (r && r.rawError) || null,
                type: "Insert",
                sourceUrl:
                  sourceBaseUrl && r.oldId
                    ? `${sourceBaseUrl}/${r.oldId}`
                    : null
              });
            }
          }
        }
      }

      // 2. Update Matched
      if (matched.length > 0) {
        // matched is [{source, dest}]
        const recordsToUpdate = matched.map((m) => {
          const out = { Id: m.dest.Id }; // Use Destination ID for update
          for (const key of Object.keys(m.source)) {
            if (key === "Id") continue; // Don't overwrite ID with source ID
            // We could selectively ignore nulls here if we wanted "partial update",
            // but "Upsert" usually implies "make target look like source".
            // Note: SObject fields not in the map won't be touched.
            out[key] = m.source[key];
          }
          return out;
        });

        const results = await this.routeDestinationCall(
          () => updateRecordsCurrent({ objectName, records: recordsToUpdate }),
          () =>
            updateRecordsRemote({
              sessionId: this.destSessionId,
              instanceUrl: this.destInstanceUrl,
              objectName,
              records: recordsToUpdate
            })
        );

        if (Array.isArray(results)) {
          const sourceBaseUrl = this.isSourceCurrentOrg
            ? window.location.origin
            : this.instanceUrl;

          results.forEach((r, idx) => {
            // Map back to Source ID for reporting consistency
            const sourceId = matched[idx].source.Id;
            if (r && r.success) {
              report.successCount += 1;
              report.successes.push({
                oldId: sourceId,
                newId: r.newId,
                type: "Update",
                name: r.name,
                recordUrl: r.recordUrl
              });
            } else {
              report.errorCount += 1;
              report.errors.push({
                oldId: sourceId,
                errorMessage: (r && r.errorMessage) || "Unknown error",
                rawError: (r && r.rawError) || null,
                type: "Update",
                sourceUrl:
                  sourceBaseUrl && sourceId
                    ? `${sourceBaseUrl}/${sourceId}`
                    : null
              });
            }
          });
        }
      }

      // Save report and update counts
      const counts = res.counts || {
        sourceCount: 0,
        destCount: 0,
        matchedCount: 0
      };
      // After upsert, destination count conceptually matches source (if all successful)
      // But let's just track that we processed them.

      this.matchResultsByObject.set(objectName, { ...res, report, counts });
      this.matchResultsByObject = new Map(this.matchResultsByObject);
      this.wizard = { ...this.wizard, step: "report" };
    } catch (e) {
      this.error =
        e && e.body && e.body.message
          ? e.body.message
          : e && e.message
            ? e.message
            : "Upsert failed";
    } finally {
      this.isLoading = false;
    }
  };

  handleMatchingNext = async () => {
    if (this.wizard.index >= this.wizard.objects.length - 1) {
      // Build summary
      const rows = [];
      for (const obj of this.wizard.objects) {
        const r = this.matchResultsByObject.get(obj);
        const rep = r && r.report;
        rows.push({
          objectName: obj,
          successCount: rep ? rep.successCount : 0,
          errorCount: rep ? rep.errorCount : 0
        });
      }
      this.finalReportRows = rows;
      this.wizard = { ...this.wizard, step: "summary" };
      return;
    }
    // Move to next object
    const nextIndex = this.wizard.index + 1;
    this.wizard = { ...this.wizard, index: nextIndex, step: "select" };
    await this.loadMatchingFieldOptionsFor(this.currentWizardObject);
  };

  handlePrevObject = async () => {
    if (this.wizard.index <= 0) {
      return;
    }
    const prevIndex = this.wizard.index - 1;
    this.wizard = { ...this.wizard, index: prevIndex, step: "select" };
    await this.loadMatchingFieldOptionsFor(this.currentWizardObject);
  };

  handleStepBack = () => {
    this.wizard = { ...this.wizard, step: "select" };
  };

  handleMatchingSave = () => {
    // no-op: selections auto-saved in state; advance to results for convenience
    this.wizard = { ...this.wizard, step: "results" };
  };

  handleMatchingCheck = this.handleRunMatchingCheck;

  // Build options primarily from fields used in finalExportQueries for this object.
  // Fallback to destination creatable fields if none found.
  async loadMatchingFieldOptionsFor(objectName) {
    if (!objectName) return;
    // 1) Try from final export queries
    const queryFields = new Set();
    try {
      const defs = (this.finalExportQueries || []).filter(
        (d) => d && d.objectName === objectName
      );
      for (const d of defs) {
        const flist = (d && d.fields) || [];
        for (const f of flist) {
          if (!f || f === "Id") continue;
          queryFields.add(f);
        }
      }
    } catch (e) {
      // ignore
    }
    let fieldsArr = Array.from(queryFields);
    // 2) Fallback to creatable fields from destination current org
    if (fieldsArr.length === 0) {
      try {
        const map = await getCreateableFieldsCurrent({
          objectNames: [objectName]
        });
        fieldsArr =
          map && map[objectName]
            ? map[objectName].filter((f) => f && f !== "Id")
            : [];
      } catch (e2) {
        fieldsArr = [];
      }
    }
    // Build options
    const options = fieldsArr.map((f) => ({ label: f, value: f }));
    this.matchingOptionsByObject.set(objectName, options);
    this.matchingOptionsByObject = new Map(this.matchingOptionsByObject); // force update

    if (!this.selectedMatchingFieldsByObject.has(objectName)) {
      const preset = fieldsArr.includes("Name") ? ["Name"] : [];
      this.selectedMatchingFieldsByObject.set(objectName, preset);
      this.selectedMatchingFieldsByObject = new Map(
        this.selectedMatchingFieldsByObject
      ); // force update
    }
  }

  handlePlanObjectToggle = (event) => {
    const { nodeId, isSelected } = event.detail || {};
    if (!nodeId) return;
    const root = this.clonePlanNode(this.planRoot);
    const info = this.findParentAndIndexById(root, nodeId);
    if (!info) return;
    const objectNode = info.parent.children[info.index];
    if (!objectNode) return;

    // Synchronize parent edge selection if this object is a target of an edge
    if (info.parent && info.parent.type === "edge") {
      info.parent.isSelected = !!isSelected;
    }

    const setDescendants = (node, selected) => {
      if (!node || !Array.isArray(node.children)) return;
      for (const child of node.children) {
        if (child.type === "edge") {
          child.isSelected = !!selected;
          child.lockedByAncestor = !selected;
          if (child.children && child.children[0]) {
            // lock/unlock the target object subtree
            child.children[0].lockedByAncestor = !selected;
            setDescendants(child.children[0], selected);
          }
        } else {
          child.lockedByAncestor = !selected;
          setDescendants(child, selected);
        }
      }
    };
    // Lock or unlock all descendants based on object selection
    objectNode.lockedByAncestor = !isSelected;
    setDescendants(objectNode, !!isSelected);
    this.planRoot = root;
    this.effectiveDepth = this.calculateSelectedDepth(this.planRoot);
  };

  collectSelectedEdgesFromPlan(root) {
    const map = new Map();
    const add = (fromObj, fieldName, toObj) => {
      if (!map.has(fromObj)) map.set(fromObj, []);
      map.get(fromObj).push({ fieldName, target: toObj });
    };
    const walk = (node, currentObject) => {
      if (!node) return;
      if (node.type === "object") {
        currentObject = node.objectName;
      }
      if (Array.isArray(node.children)) {
        for (const child of node.children) {
          if (child.type === "edge") {
            if (child.isSelected) {
              add(currentObject, child.fieldName, child.targetObject);
              if (child.children && child.children[0]) {
                walk(child.children[0], child.targetObject);
              }
            }
          } else {
            walk(child, currentObject);
          }
        }
      }
    };
    walk(root, root && root.objectName);
    return map;
  }
  async collectIds(order, limit, edgesByObject) {
    const queried = new Map();
    const pending = new Map();

    for (const objectName of order) {
      this.ensureObjectEntry(objectName, queried, pending);
    }

    const bootstrapObjects = this.getBootstrapObjects(order, edgesByObject);
    for (const objectName of bootstrapObjects) {
      await this.queryAndProcess(
        objectName,
        { limit },
        edgesByObject,
        queried,
        pending
      );
    }

    while (true) {
      let madeProgress = false;

      for (let idx = order.length - 1; idx >= 0; idx -= 1) {
        const objectName = order[idx];
        const pendingSet = pending.get(objectName);
        if (!pendingSet || pendingSet.size === 0) {
          continue;
        }
        const idsToQuery = Array.from(pendingSet).filter(
          (id) => id && !queried.get(objectName).has(id)
        );
        if (!idsToQuery.length) {
          pendingSet.clear();
          continue;
        }
        await this.queryAndProcess(
          objectName,
          { ids: idsToQuery },
          edgesByObject,
          queried,
          pending
        );
        pendingSet.clear();
        madeProgress = true;
      }

      if (!madeProgress) {
        break;
      }

      const stillPending = order.some((objectName) => {
        const set = pending.get(objectName);
        if (!set || set.size === 0) {
          return false;
        }
        for (const id of set) {
          if (id && !queried.get(objectName).has(id)) {
            return true;
          }
        }
        return false;
      });

      if (!stillPending) {
        break;
      }
    }

    return queried;
  }

  ensureObjectEntry(objectName, queried, pending) {
    if (!queried.has(objectName)) {
      queried.set(objectName, new Set());
    }
    if (!pending.has(objectName)) {
      pending.set(objectName, new Set());
    }
  }

  getBootstrapObjects(order, edgesByObject) {
    if (!order || !order.length) {
      return [];
    }
    const referencedAsTarget = new Set();
    for (const edges of edgesByObject.values()) {
      for (const edge of edges) {
        referencedAsTarget.add(edge.target);
      }
    }
    const candidates = order.filter(
      (objectName) => !referencedAsTarget.has(objectName)
    );
    // Prefer to bootstrap objects that still have selected outgoing edges
    const withEdges = candidates.filter((obj) => {
      const edges = edgesByObject.get(obj) || [];
      return edges.length > 0;
    });
    if (withEdges.length) {
      return withEdges;
    }
    // If none have edges (e.g., depth 0 or a leaf/root-only export),
    // bootstrap the first object in the order (root prioritized in order)
    return [order[0]];
  }

  async queryAndProcess(objectName, options, edgesByObject, queried, pending) {
    this.ensureObjectEntry(objectName, queried, pending);
    const edges = edgesByObject.get(objectName) || [];
    const fieldSet = new Set();
    for (const edge of edges) {
      if (edge.fieldName) {
        fieldSet.add(edge.fieldName);
      }
    }
    const fieldList = Array.from(fieldSet);
    const selectClause = fieldList.length
      ? `Id, ${fieldList.join(", ")}`
      : "Id";

    if (options.ids && options.ids.length) {
      const batches = this.chunkArray(options.ids, 200);
      for (const batch of batches) {
        const cleaned = batch.filter(Boolean);
        if (!cleaned.length) {
          continue;
        }
        const where = cleaned
          .map((id) => `'${id.replace(/'/g, "\'")}'`)
          .join(",");
        const soql = `SELECT ${selectClause} FROM ${objectName} WHERE Id IN (${where})`;
        await this.processQueryRows(objectName, soql, edges, queried, pending);
      }
    } else {
      // Bootstrap query: even if there are no selected outgoing edges, we still need Ids
      const soql = `SELECT ${selectClause} FROM ${objectName} LIMIT ${options.limit}`;
      await this.processQueryRows(objectName, soql, edges, queried, pending);
    }
  }

  async processQueryRows(objectName, soql, edges, queried, pending) {
    const result = await this.runQueryWithSession(soql);
    const rows = (result && result.rows) || [];
    const objectSet = queried.get(objectName);
    for (const row of rows) {
      if (!row) {
        continue;
      }
      const rowId = row.Id;
      if (rowId) {
        objectSet.add(rowId);
      }
      for (const edge of edges) {
        const rawValue = edge.fieldName ? row[edge.fieldName] : undefined;
        if (!rawValue) {
          continue;
        }
        this.ensureObjectEntry(edge.target, queried, pending);
        const targetPending = pending.get(edge.target);
        const targetQueried = queried.get(edge.target);
        const values = Array.isArray(rawValue) ? rawValue : [rawValue];
        for (const value of values) {
          if (!value) {
            continue;
          }
          const candidate =
            typeof value === "object" && value !== null ? value.Id : value;
          if (
            typeof candidate === "string" &&
            candidate &&
            !targetQueried.has(candidate)
          ) {
            targetPending.add(candidate);
          }
        }
      }
    }
  }

  serializeIdSets(idSetMap) {
    const output = {};
    for (const [objectName, idSet] of idSetMap.entries()) {
      output[objectName] = Array.from(idSet).sort();
    }
    return output;
  }

  chunkArray(arr, size) {
    const out = [];
    for (let i = 0; i < arr.length; i += size) {
      out.push(arr.slice(i, i + size));
    }
    return out;
  }
  async handleFinalExport() {
    // Require source connectivity for schema discovery if not current org
    if (!this.ensureSourceConnected("Please test connection first")) {
      return;
    }
    // Destination must be connected (either as current org or tested external session)
    if (
      !this.ensureDestinationConnected(
        "Please test destination connection first"
      )
    ) {
      return;
    }
    if (!this.lastQueriedIdSets || this.lastQueriedIdSets.size === 0) {
      this.error = "Run Export to collect IDs before building final queries";
      return;
    }
    const objectsWithIds = this.exportOrder.filter((objectName) => {
      const set = this.lastQueriedIdSets.get(objectName);
      return set && set.size > 0;
    });
    if (!objectsWithIds.length) {
      this.error = "No collected IDs available for final export";
      return;
    }

    this.error = undefined;
    try {
      this.isLoading = true;
      this.schemaWarnings = new Map();

      const selectedEdges = this.collectSelectedEdgesFromPlan(this.planRoot);

      // Get creatable fields from source and destination for intersection
      const sourceCreatableMap = await this.routeSourceCall(
        () => getCreateableFieldsCurrent({ objectNames: objectsWithIds }),
        () =>
          getCreateableFields({
            sessionId: this.sessionId,
            instanceUrl: this.instanceUrl,
            objectNames: objectsWithIds
          })
      );
      const destCreatableMap = await this.routeDestinationCall(
        () => getCreateableFieldsCurrent({ objectNames: objectsWithIds }),
        () =>
          getCreateableFields({
            sessionId: this.destSessionId,
            instanceUrl: this.destInstanceUrl,
            objectNames: objectsWithIds
          })
      );

      // Iterate bottom-to-top of export order (reverse order)
      const iterationOrder = objectsWithIds.slice().reverse();
      const queries = [];
      for (const objectName of iterationOrder) {
        const ids = Array.from(this.lastQueriedIdSets.get(objectName) || []);
        if (!ids.length) continue;

        const srcFields =
          (sourceCreatableMap && sourceCreatableMap[objectName]) || [];
        const dstFields =
          (destCreatableMap && destCreatableMap[objectName]) || [];
        const dstSet = new Set(dstFields);
        let intersect = srcFields.filter(
          (f) => f && f !== "Id" && f !== "OwnerId" && dstSet.has(f)
        );

        // Identify schema mismatches
        const droppedFields = srcFields.filter(
          (f) => f && f !== "Id" && f !== "OwnerId" && !dstSet.has(f)
        );
        if (droppedFields.length > 0) {
          this.schemaWarnings.set(objectName, droppedFields);
        }

        // Apply SOQL Field Constraints
        if (
          this.soqlConstraints &&
          this.soqlConstraints.fields &&
          this.soqlConstraints.objectName === objectName
        ) {
          const requested = new Set(
            this.soqlConstraints.fields.map((f) => f.toLowerCase())
          );

          // Fetch required fields to ensure we don't break insert
          let requiredFields = [];
          try {
            requiredFields = await this.routeDestinationCall(
              () => [], // Local required fields logic not strictly needed if we assume standard valid fields or could implement similarly
              () =>
                getRequiredFields({
                  sessionId: this.destSessionId,
                  instanceUrl: this.destInstanceUrl,
                  objectName
                })
            );
          } catch (reqErr) {
            console.warn("Failed to fetch required fields", reqErr);
          }
          const requiredSet = new Set(
            (requiredFields || []).map((f) => f.toLowerCase())
          );

          // Filter intersect: keep if requested OR required
          intersect = intersect.filter((f) => {
            const flow = f.toLowerCase();
            return requested.has(flow) || requiredSet.has(flow);
          });
        }

        // Filter out deselected relationship fields based on the plan (DEFINITIVE FILTER)
        const allEdgesForObj = this.planEdges.get(objectName) || [];
        const selectedEdgesForObj = selectedEdges.get(objectName) || [];
        const selectedFieldNames = new Set(
          selectedEdgesForObj.map((e) => (e.fieldName || "").toLowerCase())
        );

        intersect = intersect.filter((f) => {
          const fieldLow = (f || "").toLowerCase();
          // If this field is a relationship field in our plan, it must be selected
          const planEdge = allEdgesForObj.find(
            (e) => (e.fieldName || "").toLowerCase() === fieldLow
          );
          if (planEdge) {
            return selectedFieldNames.has(fieldLow);
          }
          return true; // Not a relationship field in the plan, keep it
        });

        const uniqueFields = ["Id", ...intersect];
        const selectClause = uniqueFields.join(", ");

        for (const batch of this.chunkArray(ids, 200)) {
          const where = batch
            .filter(Boolean)
            .map((id) => `'${id.replace(/'/g, "\'")}'`)
            .join(",");
          if (!where) continue;
          const soql = `SELECT ${selectClause} FROM ${objectName} WHERE Id IN (${where})`;
          queries.push({
            objectName,
            count: batch.length,
            soql,
            fields: uniqueFields
          });
        }
      }

      this.finalExportQueries = queries;
      // Reset import status/reporting when final queries change
      this.importStatus = {
        inProgress: false,
        currentObject: "",
        processedObjects: 0,
        totalObjects: 0,
        successCount: 0,
        errorCount: 0,
        detailedMessages: []
      };
      this.successReportLines = [];
      this.errorReportLines = [];
      console.log(
        JSON.stringify({ type: "FINAL_EXPORT_SOQL", queries }, null, 2)
      );
    } catch (e) {
      this.error =
        e && e.body && e.body.message
          ? e.body.message
          : e && e.message
            ? e.message
            : "Failed to build final export queries";
      console.error("Final export error", this.error);
    } finally {
      this.isLoading = false;
    }
  }

  handleCheckMatchingDestination = () => {
    // Placeholder for later implementation

    console.log("Check Matching in Destination clicked");
  };

  computeExportOrder(edgesByObject, rootObject, idSetKeys = []) {
    // Build nodes, adjacency (parent -> children), and in-degree(children)
    const nodes = new Set(idSetKeys || []);
    const adj = new Map();
    const inDegree = new Map();

    const ensureNode = (n) => {
      if (!inDegree.has(n)) inDegree.set(n, 0);
    };

    for (const [fromObj, edges] of edgesByObject.entries()) {
      nodes.add(fromObj);
      ensureNode(fromObj);
      for (const e of edges) {
        nodes.add(e.target);
        ensureNode(e.target);
        // Edge: parent (target) -> child (fromObj)
        if (!adj.has(e.target)) adj.set(e.target, new Set());
        if (!adj.get(e.target).has(fromObj)) {
          adj.get(e.target).add(fromObj);
          inDegree.set(fromObj, (inDegree.get(fromObj) || 0) + 1);
        }
      }
    }

    // Ensure all idSetKeys exist in maps
    for (const n of nodes) ensureNode(n);

    // Kahn's algorithm with tie-breaker: prioritize root when it becomes available
    const order = [];
    const inQueue = new Set();
    const queue = [];

    const enqueue = (n, prioritize = false) => {
      if (inQueue.has(n)) return;
      if (prioritize) {
        queue.unshift(n);
      } else {
        queue.push(n);
      }
      inQueue.add(n);
    };

    for (const n of nodes) {
      if ((inDegree.get(n) || 0) === 0) enqueue(n, n === rootObject);
    }

    while (queue.length) {
      const n = queue.shift();
      order.push(n);
      const children = Array.from(adj.get(n) || []);
      for (const c of children) {
        inDegree.set(c, (inDegree.get(c) || 0) - 1);
        if ((inDegree.get(c) || 0) === 0) enqueue(c, c === rootObject);
      }
    }

    // Add any isolated nodes not reached
    for (const n of nodes) {
      if (!order.includes(n)) order.push(n);
    }

    return order;
  }

  async handleCheckPlan(autoApply = false) {
    // Require an object, and if using external session, require a tested connection
    if (!this.selectedObject) {
      this.error =
        "Please select an object and ensure connection is established";
      return;
    }
    if (
      !this.ensureSourceConnected(
        "Please select an object and ensure connection is established"
      )
    ) {
      return;
    }

    this.error = undefined;
    this.isLoading = true;

    try {
      console.log(
        "Checking dependencies for:",
        this.selectedObject,
        "with depth:",
        this.maxDepth,
        "excluding:",
        this.excludedObjects
      );
      const paramsCurrent = {
        objectName: this.selectedObject,
        maxDepth: this.maxDepth,
        excludedObjects: this.excludedObjects
      };
      const paramsSession = {
        sessionId: this.sessionId,
        instanceUrl: this.instanceUrl,
        objectName: this.selectedObject,
        maxDepth: this.maxDepth,
        excludedObjects: this.excludedObjects
      };
      const dependencies = await this.routeSourceCall(
        () => getObjectDependenciesCurrent(paramsCurrent),
        () => getObjectDependencies(paramsSession)
      );
      // Fallback: if no dependencies returned, build a minimal tree with only the selected object
      const dep = dependencies || {
        objectName: this.selectedObject,
        parents: []
      };
      this.dependencyTree = dep;
      this.buildPlanState(dep);
      // Collapse all nodes initially after building the plan,
      // then re-open the root so only descendants are collapsed
      try {
        this.handleCollapseAll();
        if (this.planRoot) {
          const clone = this.clonePlanNode(this.planRoot);
          clone.isCollapsed = false;
          this.planRoot = clone;
        }
      } catch (e) {
        /* no-op */
      }
      console.log(
        JSON.stringify(
          {
            type: "EXPORT_PLAN",
            root: this.selectedObject,
            order: this.exportOrder
          },
          null,
          2
        )
      );

      console.log("Dependencies retrieved:", dependencies);

      if (autoApply && this.soqlConstraints) {
        this.applySoqlConstraints();
      }
    } catch (e) {
      this.error =
        e && e.body && e.body.message
          ? e.body.message
          : e && e.message
            ? e.message
            : "Failed to get dependencies";
      console.error("Error getting dependencies", this.error);
      this.dependencyTree = undefined;
      this.planRoot = undefined;
      this.planEdges = new Map();
      this.exportOrder = [];
      this.planReady = false;
    } finally {
      this.isLoading = false;
    }
  }

  resetObjectSelection() {
    this.showObjectPicker = false;
    this.availableObjects = [];
    this.selectedObject = undefined;
    this.dependencyTree = undefined;
    this.sessionId = undefined;
    this.instanceUrl = undefined;
    this.maxDepth = undefined;
    this.excludedObjects = [];
    this.planRoot = undefined;
    this.planEdges = new Map();
    this.exportOrder = [];
    this.planReady = false;
    this.lastQueriedIdSets = new Map();
    this.lastQueriedIdSnapshot = undefined;
    this.exportStats = undefined;
    this.effectiveDepth = undefined;
  }

  clearSourceSession() {
    this.sessionId = undefined;
    this.instanceUrl = undefined;
    this.testMessage = undefined;
  }

  handleReverseOrgs = () => {
    // Swap credentials and environments between Source and Destination
    this.debug("Reversing orgs");
    const sU = this.username;
    const sP = this.password;
    const sE = this.environment;

    this.username = this.destUsername || "";
    this.password = this.destPassword || "";
    this.environment = this.destEnvironment || "Production";

    this.destUsername = sU || "";
    this.destPassword = sP || "";
    this.destEnvironment = sE || "Production";

    // Swap current-org selection if set
    if (this.currentOrgFor === "source") {
      this.currentOrgFor = "destination";
    } else if (this.currentOrgFor === "destination") {
      this.currentOrgFor = "source";
    }

    // Clear connection states and UI dependent on source
    this.clearSourceSession();
    this.destSessionId = undefined;
    this.destInstanceUrl = undefined;
    this.destTestMessage = undefined;
    this.error = undefined;
    this.resetObjectSelection();
    // If source is now current org, prefetch objects
    if (this.isSourceCurrentOrg) {
      this.fetchAvailableObjectsSource();
    }
    // Sync the picklist UI to reflect currentOrgFor
    this.sourceUseCurrent = this.isSourceCurrentOrg ? "yes" : "no";
    this.destUseCurrent = this.isDestinationCurrentOrg ? "yes" : "no";
  };
}

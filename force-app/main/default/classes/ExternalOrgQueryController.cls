public with sharing class ExternalOrgQueryController {
  // Controller to authenticate to another Salesforce org via SOAP login
  // and run SOQL via REST, returning results to a Lightning Web Component.
  // NOW REFACTORED TO USE SERVICE CLASSES.

  @AuraEnabled(cacheable=false)
  public static ExternalOrgQueryService.QueryResultWrapper loginAndQuery(
    String username,
    String password,
    String environment,
    String soql
  ) {
    return ExternalOrgQueryService.loginAndQuery(
      username,
      password,
      environment,
      soql
    );
  }

  @AuraEnabled(cacheable=false)
  public static ExternalOrgAuthService.ConnectionTestResult testConnection(
    String username,
    String password,
    String environment
  ) {
    return ExternalOrgAuthService.testConnection(
      username,
      password,
      environment
    );
  }

  @AuraEnabled(cacheable=false)
  public static List<String> getAvailableObjects(
    String sessionId,
    String instanceUrl
  ) {
    return ExternalOrgDescribeService.getAvailableObjects(
      sessionId,
      instanceUrl
    );
  }

  @AuraEnabled(cacheable=false)
  public static ExternalOrgDescribeService.DependencyNode getObjectDependencies(
    String sessionId,
    String instanceUrl,
    String objectName,
    Integer maxDepth,
    List<String> excludedObjects
  ) {
    return ExternalOrgDescribeService.getObjectDependencies(
      sessionId,
      instanceUrl,
      objectName,
      maxDepth,
      excludedObjects
    );
  }

  @AuraEnabled(cacheable=false)
  public static List<String> getRequiredFields(
    String sessionId,
    String instanceUrl,
    String objectName
  ) {
    return ExternalOrgDescribeService.getRequiredFields(
      sessionId,
      instanceUrl,
      objectName
    );
  }

  @AuraEnabled(cacheable=false)
  public static Map<String, List<String>> getCreateableFields(
    String sessionId,
    String instanceUrl,
    List<String> objectNames
  ) {
    return ExternalOrgDescribeService.getCreateableFields(
      sessionId,
      instanceUrl,
      objectNames
    );
  }

  @AuraEnabled(cacheable=false)
  public static ExternalOrgQueryService.QueryResultWrapper queryWithSession(
    String sessionId,
    String instanceUrl,
    String soql
  ) {
    return ExternalOrgQueryService.queryWithSession(
      sessionId,
      instanceUrl,
      soql
    );
  }

  @AuraEnabled(cacheable=false)
  public static ExternalOrgQueryService.QueryResultWrapper queryByUrl(
    String sessionId,
    String instanceUrl,
    String url
  ) {
    return ExternalOrgQueryService.queryByUrl(sessionId, instanceUrl, url);
  }

  // =====================
  // Current-org operations
  // =====================
  @AuraEnabled(cacheable=false)
  public static List<String> getAvailableObjectsCurrent() {
    return ExternalOrgDescribeService.getAvailableObjectsCurrent();
  }

  @AuraEnabled(cacheable=false)
  public static ExternalOrgQueryService.QueryResultWrapper queryCurrent(
    String soql
  ) {
    return ExternalOrgQueryService.queryCurrent(soql);
  }

  @AuraEnabled(cacheable=false)
  public static ExternalOrgDescribeService.DependencyNode getObjectDependenciesCurrent(
    String objectName,
    Integer maxDepth,
    List<String> excludedObjects
  ) {
    return ExternalOrgDescribeService.getObjectDependenciesCurrent(
      objectName,
      maxDepth,
      excludedObjects
    );
  }

  @AuraEnabled(cacheable=false)
  public static Map<String, List<String>> getCreateableFieldsCurrent(
    List<String> objectNames
  ) {
    return ExternalOrgDescribeService.getCreateableFieldsCurrent(objectNames);
  }

  @AuraEnabled(cacheable=false)
  public static String getBatchReport(String jobId) {
    return DataSeedingService.getBatchReport(jobId);
  }

  @AuraEnabled(cacheable=false)
  public static List<ExternalOrgDmlService.InsertMapping> insertRecordsCurrent(
    String objectName,
    List<Map<String, Object>> records
  ) {
    return ExternalOrgDmlService.insertRecordsCurrent(objectName, records);
  }

  @AuraEnabled(cacheable=false)
  public static List<ExternalOrgDmlService.InsertMapping> updateRecordsCurrent(
    String objectName,
    List<Map<String, Object>> records
  ) {
    return ExternalOrgDmlService.updateRecordsCurrent(objectName, records);
  }

  // =====================
  // Remote (REST) Write Operations
  // =====================

  @AuraEnabled(cacheable=false)
  public static List<ExternalOrgDmlService.InsertMapping> createRecordsRemote(
    String sessionId,
    String instanceUrl,
    String objectName,
    List<Map<String, Object>> records
  ) {
    return ExternalOrgDmlService.createRecordsRemote(
      sessionId,
      instanceUrl,
      objectName,
      records
    );
  }

  @AuraEnabled(cacheable=false)
  public static List<ExternalOrgDmlService.InsertMapping> updateRecordsRemote(
    String sessionId,
    String instanceUrl,
    String objectName,
    List<Map<String, Object>> records
  ) {
    return ExternalOrgDmlService.updateRecordsRemote(
      sessionId,
      instanceUrl,
      objectName,
      records
    );
  }

  @AuraEnabled(cacheable=false)
  public static List<DataSeedingService.MatchResult> findMatchingRecords(
    String sessionId,
    String instanceUrl,
    String objectName,
    List<String> matchFields,
    List<Map<String, Object>> sourceRecords
  ) {
    return DataSeedingService.findMatchingRecords(
      sessionId,
      instanceUrl,
      objectName,
      matchFields,
      sourceRecords
    );
  }

  @AuraEnabled(cacheable=false)
  public static Map<String, List<ExternalOrgDescribeService.FieldMetadata>> getFieldMetadata(
    String sessionId,
    String instanceUrl,
    List<String> objectNames
  ) {
    return ExternalOrgDescribeService.getFieldMetadata(
      sessionId,
      instanceUrl,
      objectNames
    );
  }

  @AuraEnabled(cacheable=false)
  public static Map<String, List<ExternalOrgDescribeService.FieldMetadata>> getFieldMetadataCurrent(
    List<String> objectNames
  ) {
    return ExternalOrgDescribeService.getFieldMetadataCurrent(objectNames);
  }

  @AuraEnabled
  public static String startDataSeedingBatch(
    String sourceSessionId,
    String sourceInstanceUrl,
    String destSessionId,
    String destInstanceUrl,
    List<Map<String, Object>> tasks,
    Map<String, Map<String, String>> planEdges
  ) {
    return DataSeedingService.startDataSeedingBatch(
      sourceSessionId,
      sourceInstanceUrl,
      destSessionId,
      destInstanceUrl,
      tasks,
      planEdges
    );
  }

  @AuraEnabled
  public static AsyncApexJob getBatchJobStatus(String jobId) {
    return DataSeedingService.getBatchJobStatus(jobId);
  }

  @AuraEnabled(cacheable=false)
  public static List<ExternalOrgDmlService.InsertMapping> importRecordsWithResolution(
    String sourceSessionId,
    String sourceInstanceUrl,
    String destSessionId,
    String destInstanceUrl,
    String objectName,
    List<Map<String, Object>> records
  ) {
    try {
      List<Map<String, Object>> processed = DataSeedingService.preprocessRecords(
        objectName,
        records,
        sourceSessionId,
        sourceInstanceUrl,
        destSessionId,
        destInstanceUrl
      );

      if (
        String.isNotBlank(destSessionId) && String.isNotBlank(destInstanceUrl)
      ) {
        return ExternalOrgDmlService.createRecordsRemote(
          destSessionId,
          destInstanceUrl,
          objectName,
          processed
        );
      } else {
        return ExternalOrgDmlService.insertRecordsCurrent(
          objectName,
          processed
        );
      }
    } catch (Exception e) {
      System.debug('importRecordsWithResolution error: ' + e.getMessage());
      throw new AuraHandledException(e.getMessage());
    }
  }
}

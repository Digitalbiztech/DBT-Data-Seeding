public with sharing class ExternalOrgDescribeService {
  public class DependencyNode {
    @AuraEnabled
    public String objectName;
    @AuraEnabled
    public String fieldName;
    @AuraEnabled
    public String relationshipName;
    @AuraEnabled
    public String relationshipType; // 'Lookup' or 'MasterDetail' or 'Child'
    @AuraEnabled
    public List<DependencyNode> parents;
    @AuraEnabled
    public List<DependencyNode> children;
    @AuraEnabled
    public Boolean isRequired;

    public DependencyNode() {
      this.parents = new List<DependencyNode>();
      this.children = new List<DependencyNode>();
      this.isRequired = false;
    }

    public DependencyNode(String objectName, String fieldName) {
      this();
      this.objectName = objectName;
      this.fieldName = fieldName;
    }
  }

  public class FieldMetadata {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String apiName;
    @AuraEnabled
    public String type;

    public FieldMetadata(String label, String apiName, String type) {
      this.label = label;
      this.apiName = apiName;
      this.type = type;
    }
  }

  private static Map<String, Map<String, Object>> describeCache = new Map<String, Map<String, Object>>();

  private static final Set<String> IGNORED_CHILD_OBJECTS = new Set<String>{
    'ActivityHistory',
    'OpenActivity',
    'AttachedContentDocument',
    'CombinedAttachment',
    'ContentDocumentLink',
    'EntitySubscription',
    'FeedComment',
    'FeedItem',
    'Note',
    'NoteAndAttachment',
    'ProcessInstance',
    'ProcessInstanceHistory',
    'RecordAction',
    'TopicAssignment',
    'LookedUpFromActivity',
    'EmailMessage',
    'Task',
    'Event',
    'ActionPlan',
    'RecordActionHistory',
    'FlowRecordRelation',
    'AIInsightValue',
    'AIRecordInsight',
    'FlowOrchestrationWorkItem',
    'UserDefinedLabelAssignment',
    'AdvAcctForecastFactAdj'
  };

  public static List<String> getAvailableObjects(
    String sessionId,
    String instanceUrl
  ) {
    System.debug('ExternalOrgDescribeService.getAvailableObjects invoked');
    try {
      if (String.isBlank(sessionId) || String.isBlank(instanceUrl)) {
        throw new CalloutException('SessionId and instanceUrl are required.');
      }

      HttpRequest request = new HttpRequest();
      request.setMethod('GET');
      request.setEndpoint(instanceUrl + '/services/data/v62.0/sobjects/');
      request.setHeader('Authorization', 'Bearer ' + sessionId);
      request.setHeader('Content-Type', 'application/json');

      Http http = new Http();
      System.debug('Sending REST callout to: ' + request.getEndpoint());
      HTTPResponse response = http.send(request);

      if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
        throw new CalloutException(
          'Failed to get objects: ' +
            response.getStatus() +
            ' ' +
            response.getBody()
        );
      }

      Map<String, Object> untyped = (Map<String, Object>) JSON.deserializeUntyped(
        response.getBody()
      );
      List<Object> sobjects = (List<Object>) untyped.get('sobjects');

      List<String> objectNames = new List<String>();
      if (sobjects != null) {
        for (Object sobj : sobjects) {
          Map<String, Object> objMap = (Map<String, Object>) sobj;
          String apiName = (String) objMap.get('name');
          Boolean queryable = (Boolean) objMap.get('queryable');
          if (String.isNotBlank(apiName) && queryable != null && queryable) {
            objectNames.add(apiName);
          }
        }
      }

      objectNames.sort();
      return objectNames;
    } catch (Exception e) {
      System.debug('getAvailableObjects Error: ' + e.getMessage());
      AuraHandledException ahe = new AuraHandledException(e.getMessage());
      ahe.setMessage(e.getMessage());
      throw ahe;
    }
  }

  public static DependencyNode getObjectDependencies(
    String sessionId,
    String instanceUrl,
    String objectName,
    Integer maxDepth,
    List<String> excludedObjects
  ) {
    System.debug(
      'ExternalOrgDescribeService.getObjectDependencies invoked for: ' +
      objectName
    );
    try {
      if (
        String.isBlank(sessionId) ||
        String.isBlank(instanceUrl) ||
        String.isBlank(objectName)
      ) {
        throw new CalloutException(
          'SessionId, instanceUrl, and objectName are required.'
        );
      }

      if (maxDepth != null && maxDepth < 0) {
        maxDepth = 0;
      }
      if (excludedObjects == null) {
        excludedObjects = new List<String>();
      }

      Set<String> excludedSet = new Set<String>();
      for (String s : excludedObjects) {
        if (String.isNotBlank(s))
          excludedSet.add(s.toLowerCase());
      }

      prefetchMetadata(
        sessionId,
        instanceUrl,
        objectName,
        maxDepth,
        excludedSet
      );

      Set<String> visited = new Set<String>();
      return buildDependencyTree(
        sessionId,
        instanceUrl,
        objectName,
        visited,
        maxDepth,
        excludedSet,
        0
      );
    } catch (Exception e) {
      System.debug('getObjectDependencies Error: ' + e.getMessage());
      AuraHandledException ahe = new AuraHandledException(e.getMessage());
      ahe.setMessage(e.getMessage());
      throw ahe;
    }
  }

  private static void prefetchMetadata(
    String sessionId,
    String instanceUrl,
    String rootObject,
    Integer maxDepth,
    Set<String> excludedObjects
  ) {
    Set<String> currentLevel = new Set<String>{ rootObject };
    Set<String> visited = new Set<String>();

    Integer depth = 0;
    while (!currentLevel.isEmpty()) {
      Set<String> nextLevel = new Set<String>();
      Set<String> neededDescriptions = new Set<String>();

      for (String obj : currentLevel) {
        if (visited.contains(obj) || excludedObjects.contains(obj))
          continue;
        visited.add(obj);
        if (!describeCache.containsKey(obj)) {
          neededDescriptions.add(obj);
        } else {
          collectParents(
            describeCache.get(obj),
            nextLevel,
            excludedObjects,
            depth,
            maxDepth
          );
        }
      }

      if (!neededDescriptions.isEmpty()) {
        executeBatchDescribe(sessionId, instanceUrl, neededDescriptions);
        for (String obj : neededDescriptions) {
          Map<String, Object> description = describeCache.get(obj);
          collectParents(
            description,
            nextLevel,
            excludedObjects,
            depth,
            maxDepth
          );
        }
      }

      if (nextLevel.isEmpty())
        break;
      currentLevel = nextLevel;
      depth++;
    }
  }

  private static void collectParents(
    Map<String, Object> description,
    Set<String> nextLevel,
    Set<String> excludedObjects,
    Integer currentDepth,
    Integer maxDepth
  ) {
    if (description == null)
      return;
    List<Object> fields = (List<Object>) description.get('fields');
    if (fields != null) {
      for (Object fieldObj : fields) {
        Map<String, Object> field = (Map<String, Object>) fieldObj;
        String fieldType = (String) field.get('type');
        List<Object> referenceTo = (List<Object>) field.get('referenceTo');
        Boolean createable = (Boolean) field.get('createable');
        Boolean nillable = (Boolean) field.get('nillable');
        Boolean defaultedOnCreate = (Boolean) field.get('defaultedOnCreate');

        if (
          fieldType == 'reference' &&
          referenceTo != null &&
          createable == true
        ) {
          String fname = (String) field.get('name');
          if (fname == 'CreatedById' || fname == 'LastModifiedById')
            continue;

          Boolean isRequired =
            (nillable == false) && (defaultedOnCreate != true);
          Boolean include = false;

          if (maxDepth == null) {
            include = true;
          } else {
            if (currentDepth < maxDepth) {
              include = true;
            } else {
              if (isRequired)
                include = true;
            }
          }

          if (include) {
            for (Object ref : referenceTo) {
              String parentName = (String) ref;
              if (
                !excludedObjects.contains(parentName.toLowerCase()) &&
                !IGNORED_CHILD_OBJECTS.contains(parentName)
              ) {
                nextLevel.add(parentName);
              }
            }
          }
        }
      }
    }
  }

  private static void executeBatchDescribe(
    String sessionId,
    String instanceUrl,
    Set<String> objectNames
  ) {
    System.debug(
      'Executing batch describe for ' + objectNames.size() + ' objects.'
    );
    List<String> batch = new List<String>();
    for (String obj : objectNames) {
      batch.add(obj);
      if (batch.size() == 25) {
        sendBatchRequest(sessionId, instanceUrl, batch);
        batch.clear();
      }
    }
    if (!batch.isEmpty()) {
      sendBatchRequest(sessionId, instanceUrl, batch);
    }
  }

  private static void sendBatchRequest(
    String sessionId,
    String instanceUrl,
    List<String> objectNames
  ) {
    Map<String, Object> requestBody = new Map<String, Object>();
    List<Map<String, Object>> batchRequests = new List<Map<String, Object>>();

    for (String obj : objectNames) {
      Map<String, Object> req = new Map<String, Object>();
      req.put('method', 'GET');
      req.put('url', '/services/data/v62.0/sobjects/' + obj + '/describe/');
      req.put('referenceId', obj);
      batchRequests.add(req);
    }
    requestBody.put('batchRequests', batchRequests);

    HttpRequest request = new HttpRequest();
    request.setMethod('POST');
    request.setEndpoint(instanceUrl + '/services/data/v62.0/composite/batch');
    request.setHeader('Authorization', 'Bearer ' + sessionId);
    request.setHeader('Content-Type', 'application/json');
    request.setBody(JSON.serialize(requestBody));

    Http http = new Http();
    HTTPResponse response = http.send(request);

    if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
      Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
        response.getBody()
      );
      List<Object> results = (List<Object>) responseBody.get('results');
      if (results != null) {
        for (Object resObj : results) {
          Map<String, Object> res = (Map<String, Object>) resObj;
          Integer statusCode = (Integer) res.get('statusCode');
          String refId = (String) res.get('referenceId');

          if (statusCode >= 200 && statusCode < 300) {
            Map<String, Object> result = (Map<String, Object>) res.get(
              'result'
            );
            describeCache.put(refId, result);
          } else {
            System.debug(
              'Failed to describe ' + refId + ' in batch: ' + res.get('result')
            );
            describeCache.put(refId, null);
          }
        }
      }
    } else {
      System.debug('Batch describe callout failed: ' + response.getStatus());
    }
  }

  private static DependencyNode buildDependencyTree(
    String sessionId,
    String instanceUrl,
    String objectName,
    Set<String> visited,
    Integer maxDepth,
    Set<String> excludedObjects,
    Integer currentDepth
  ) {
    if (visited.contains(objectName))
      return null;
    if (maxDepth != null && currentDepth >= maxDepth)
      return null;
    if (excludedObjects.contains(objectName))
      return null;

    visited.add(objectName);

    DependencyNode rootNode = new DependencyNode();
    rootNode.objectName = objectName;
    rootNode.fieldName = '';

    try {
      Map<String, Object> untyped = describeSObject(
        sessionId,
        instanceUrl,
        objectName
      );
      if (untyped == null) {
        System.debug('Describe returned null for object ' + objectName);
        return rootNode;
      }
      List<Object> fields = (List<Object>) untyped.get('fields');
      List<Object> childRels = (List<Object>) untyped.get('childRelationships');

      if (fields != null) {
        for (Object fieldObj : fields) {
          Map<String, Object> field = (Map<String, Object>) fieldObj;
          String fieldType = (String) field.get('type');
          String relationshipName = (String) field.get('relationshipName');
          List<Object> referenceTo = (List<Object>) field.get('referenceTo');
          Boolean createable = (Boolean) field.get('createable');
          Boolean nillable = (Boolean) field.get('nillable');
          Boolean defaultedOnCreate = (Boolean) field.get('defaultedOnCreate');

          if (
            fieldType == 'reference' &&
            String.isNotBlank(relationshipName) &&
            referenceTo != null &&
            !referenceTo.isEmpty() &&
            createable != null &&
            createable
          ) {
            String fieldName = (String) field.get('name');
            if (fieldName == 'CreatedById' || fieldName == 'LastModifiedById')
              continue;

            for (Object ref : referenceTo) {
              String parentObjectName = (String) ref;
              if (
                excludedObjects.contains(parentObjectName.toLowerCase()) ||
                IGNORED_CHILD_OBJECTS.contains(parentObjectName)
              )
                continue;

              DependencyNode parentNode = new DependencyNode(
                parentObjectName,
                fieldName
              );
              parentNode.relationshipName = relationshipName;
              parentNode.relationshipType = 'Lookup';
              parentNode.isRequired =
                (nillable == false) && (defaultedOnCreate != true);

              Boolean include = false;
              if (maxDepth == null) {
                include = true;
              } else {
                if (currentDepth < maxDepth) {
                  include = true;
                } else {
                  if (parentNode.isRequired)
                    include = true;
                }
              }

              if (!include)
                continue;

              DependencyNode parentTree = buildDependencyTree(
                sessionId,
                instanceUrl,
                parentObjectName,
                visited,
                maxDepth,
                excludedObjects,
                currentDepth + 1
              );
              if (parentTree != null) {
                parentNode.parents = parentTree.parents;
                parentNode.children = parentTree.children;
              }

              rootNode.parents.add(parentNode);
            }
          }
        }
      }
    } catch (Exception e) {
      System.debug(
        'Error building dependency tree for ' +
          objectName +
          ': ' +
          e.getMessage()
      );
    }

    visited.remove(objectName);
    return rootNode;
  }

  private static Map<String, Object> describeSObject(
    String sessionId,
    String instanceUrl,
    String objectName
  ) {
    if (String.isBlank(objectName))
      return null;
    if (describeCache.containsKey(objectName)) {
      return describeCache.get(objectName);
    }

    HttpRequest request = new HttpRequest();
    request.setMethod('GET');
    request.setEndpoint(
      instanceUrl + '/services/data/v62.0/sobjects/' + objectName + '/describe/'
    );
    request.setHeader('Authorization', 'Bearer ' + sessionId);
    request.setHeader('Content-Type', 'application/json');

    Http http = new Http();
    HTTPResponse response = http.send(request);

    if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
      System.debug(
        'Failed to describe object ' + objectName + ': ' + response.getStatus()
      );
      describeCache.put(objectName, null);
      return null;
    }

    Map<String, Object> untyped = (Map<String, Object>) JSON.deserializeUntyped(
      response.getBody()
    );
    describeCache.put(objectName, untyped);
    return untyped;
  }

  public static List<String> getRequiredFields(
    String sessionId,
    String instanceUrl,
    String objectName
  ) {
    try {
      if (
        String.isBlank(sessionId) ||
        String.isBlank(instanceUrl) ||
        String.isBlank(objectName)
      ) {
        throw new CalloutException(
          'SessionId, InstanceUrl, and ObjectName are required.'
        );
      }

      Map<String, Object> describe = describeSObject(
        sessionId,
        instanceUrl,
        objectName
      );
      List<String> required = new List<String>();
      if (describe != null) {
        List<Object> fields = (List<Object>) describe.get('fields');
        if (fields != null) {
          for (Object fieldObj : fields) {
            Map<String, Object> field = (Map<String, Object>) fieldObj;
            Boolean nillable = (Boolean) field.get('nillable');
            Boolean defaulted = (Boolean) field.get('defaultedOnCreate');
            Boolean createable = (Boolean) field.get('createable');
            String name = (String) field.get('name');

            if (createable == true && nillable == false && defaulted != true) {
              required.add(name);
            }
          }
        }
      }
      return required;
    } catch (Exception e) {
      System.debug('getRequiredFields Error: ' + e.getMessage());
      return new List<String>();
    }
  }

  public static Map<String, List<String>> getCreateableFields(
    String sessionId,
    String instanceUrl,
    List<String> objectNames
  ) {
    try {
      if (String.isBlank(sessionId) || String.isBlank(instanceUrl)) {
        throw new CalloutException('SessionId and instanceUrl are required.');
      }
      Map<String, List<String>> result = new Map<String, List<String>>();
      if (objectNames == null || objectNames.isEmpty()) {
        return result;
      }

      for (String objectName : objectNames) {
        if (String.isBlank(objectName))
          continue;
        Map<String, Object> describeResult = describeSObject(
          sessionId,
          instanceUrl,
          objectName
        );
        if (describeResult == null)
          continue;
        List<String> creatableFields = new List<String>();
        List<Object> fields = (List<Object>) describeResult.get('fields');
        if (fields != null) {
          for (Object fieldObj : fields) {
            Map<String, Object> field = (Map<String, Object>) fieldObj;
            Boolean createable = (Boolean) field.get('createable');
            Boolean defaultedOnCreate = (Boolean) field.get(
              'defaultedOnCreate'
            );
            String fieldName = (String) field.get('name');
            if (
              createable == null ||
              !createable ||
              ((defaultedOnCreate == null || defaultedOnCreate) &&
              fieldName != 'IsActive')
            ) {
              continue;
            }
            if (String.isNotBlank(fieldName)) {
              creatableFields.add(fieldName);
            }
          }
        }
        creatableFields.sort();
        if (objectName == 'User') {
          List<String> filtered = new List<String>();
          for (String f : creatableFields) {
            String low = f.toLowerCase();
            if (
              low == 'userroleid' ||
              low.contains('userlicense') ||
              low.startsWith('userpreferences') ||
              low.startsWith('userpermissions')
            ) {
              continue;
            }
            filtered.add(f);
          }
          creatableFields = filtered;
        }
        result.put(objectName, creatableFields);
      }
      return result;
    } catch (Exception e) {
      System.debug('getCreateableFields Error: ' + e.getMessage());
      AuraHandledException ahe = new AuraHandledException(e.getMessage());
      ahe.setMessage(e.getMessage());
      throw ahe;
    }
  }

  public static List<String> getAvailableObjectsCurrent() {
    List<String> names = new List<String>();
    Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
    for (String api : gd.keySet()) {
      Schema.DescribeSObjectResult d = gd.get(api).getDescribe();
      if (d.isQueryable()) {
        names.add(d.getName());
      }
    }
    names.sort();
    return names;
  }

  public static DependencyNode getObjectDependenciesCurrent(
    String objectName,
    Integer maxDepth,
    List<String> excludedObjects
  ) {
    try {
      if (String.isBlank(objectName)) {
        throw new CalloutException('objectName is required.');
      }
      if (maxDepth != null && maxDepth < 0)
        maxDepth = 0;
      if (excludedObjects == null)
        excludedObjects = new List<String>();
      Set<String> visited = new Set<String>();

      Set<String> excluded = new Set<String>();
      for (String s : excludedObjects) {
        if (String.isNotBlank(s))
          excluded.add(s.toLowerCase());
      }

      return buildDependencyTreeCurrent(
        objectName,
        visited,
        maxDepth,
        excluded,
        0
      );
    } catch (Exception e) {
      System.debug('getObjectDependenciesCurrent Error: ' + e.getMessage());
      AuraHandledException ahe = new AuraHandledException(e.getMessage());
      ahe.setMessage(e.getMessage());
      throw ahe;
    }
  }

  private static DependencyNode buildDependencyTreeCurrent(
    String objectName,
    Set<String> visited,
    Integer maxDepth,
    Set<String> excluded,
    Integer currentDepth
  ) {
    DependencyNode root = new DependencyNode();
    root.objectName = objectName;
    root.fieldName = '';

    if (visited.contains(objectName))
      return root;
    visited.add(objectName);

    try {
      Schema.SObjectType t = Schema.getGlobalDescribe().get(objectName);
      if (t == null)
        return root;
      Schema.DescribeSObjectResult d = t.getDescribe();

      if (true) {
        // Hybrid Logic: Always iterate
        for (Schema.SObjectField f : d.fields.getMap().values()) {
          Schema.DescribeFieldResult fd = f.getDescribe();
          if (
            fd.getName() == 'CreatedById' ||
            fd.getName() == 'LastModifiedById'
          )
            continue;

          if (
            fd.getType() == Schema.DisplayType.Reference &&
            String.isNotBlank(fd.getRelationshipName())
          ) {
            List<Schema.SObjectType> rTo = fd.getReferenceTo();
            if (
              rTo != null &&
              !rTo.isEmpty() &&
              fd.isCreateable() &&
              !fd.isDefaultedOnCreate()
            ) {
              for (Schema.SObjectType refType : rTo) {
                String parentName = refType.getDescribe().getName();
                if (
                  !excluded.contains(parentName.toLowerCase()) &&
                  !IGNORED_CHILD_OBJECTS.contains(parentName)
                ) {
                  DependencyNode parentNode = new DependencyNode(
                    parentName,
                    fd.getName()
                  );
                  parentNode.relationshipName = fd.getRelationshipName();
                  parentNode.relationshipType = 'Lookup';
                  parentNode.isRequired =
                    (!fd.isNillable()) && (!fd.isDefaultedOnCreate());

                  Boolean include = false;
                  if (maxDepth == null) {
                    include = true;
                  } else {
                    if (currentDepth < maxDepth) {
                      include = true;
                    } else {
                      if (parentNode.isRequired)
                        include = true;
                    }
                  }

                  if (!include)
                    continue;

                  DependencyNode parentTree = buildDependencyTreeCurrent(
                    parentName,
                    visited,
                    maxDepth,
                    excluded,
                    currentDepth + 1
                  );
                  if (parentTree != null) {
                    parentNode.parents = parentTree.parents;
                    parentNode.children = parentTree.children;
                  }
                  root.parents.add(parentNode);
                }
              }
            }
          }
        }
      }
    } catch (Exception e) {
      System.debug(
        'Error building current-org dependency tree for ' +
          objectName +
          ': ' +
          e.getMessage()
      );
    }

    visited.remove(objectName);
    return root;
  }

  public static Map<String, List<String>> getCreateableFieldsCurrent(
    List<String> objectNames
  ) {
    Map<String, List<String>> out = new Map<String, List<String>>();
    if (objectNames == null)
      return out;
    Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
    for (String name : objectNames) {
      if (String.isBlank(name))
        continue;
      Schema.SObjectType t = gd.get(name);
      if (t == null) {
        out.put(name, new List<String>());
        continue;
      }
      Schema.DescribeSObjectResult d = t.getDescribe();
      List<String> fields = new List<String>();
      for (Schema.SObjectField f : d.fields.getMap().values()) {
        Schema.DescribeFieldResult fd = f.getDescribe();
        if (
          fd.isCreateable() &&
          (!fd.isDefaultedOnCreate() || fd.getName() == 'IsActive')
        ) {
          fields.add(fd.getName());
        }
      }
      fields.sort();
      if (name == 'User') {
        List<String> filtered = new List<String>();
        for (String f : fields) {
          String low = f.toLowerCase();
          if (
            low == 'userroleid' ||
            low.contains('userlicense') ||
            low.startsWith('userpreferences') ||
            low.startsWith('userpermissions')
          ) {
            continue;
          }
          filtered.add(f);
        }
        fields = filtered;
      }
      out.put(name, fields);
    }
    return out;
  }

  public static Map<String, List<FieldMetadata>> getFieldMetadata(
    String sessionId,
    String instanceUrl,
    List<String> objectNames
  ) {
    Map<String, List<FieldMetadata>> result = new Map<String, List<FieldMetadata>>();
    if (objectNames == null || objectNames.isEmpty())
      return result;

    for (String objName : objectNames) {
      Map<String, Object> describe = describeSObject(
        sessionId,
        instanceUrl,
        objName
      );
      if (describe == null)
        continue;

      List<FieldMetadata> metaList = new List<FieldMetadata>();
      List<Object> fields = (List<Object>) describe.get('fields');
      if (fields != null) {
        for (Object fObj : fields) {
          Map<String, Object> f = (Map<String, Object>) fObj;
          metaList.add(
            new FieldMetadata(
              (String) f.get('label'),
              (String) f.get('name'),
              (String) f.get('type')
            )
          );
        }
      }
      result.put(objName, metaList);
    }
    return result;
  }

  public static Map<String, List<FieldMetadata>> getFieldMetadataCurrent(
    List<String> objectNames
  ) {
    Map<String, List<FieldMetadata>> result = new Map<String, List<FieldMetadata>>();
    if (objectNames == null || objectNames.isEmpty())
      return result;

    Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
    for (String objName : objectNames) {
      Schema.SObjectType t = gd.get(objName);
      if (t == null)
        continue;

      Schema.DescribeSObjectResult d = t.getDescribe();
      List<FieldMetadata> metaList = new List<FieldMetadata>();
      for (Schema.SObjectField f : d.fields.getMap().values()) {
        Schema.DescribeFieldResult fd = f.getDescribe();
        metaList.add(
          new FieldMetadata(
            fd.getLabel(),
            fd.getName(),
            String.valueOf(fd.getType()).toLowerCase()
          )
        );
      }
      result.put(objName, metaList);
    }
    return result;
  }

  public static Map<String, String> getReferenceFields(
    String sessionId,
    String instanceUrl,
    String objectName
  ) {
    Map<String, String> refMap = new Map<String, String>();
    try {
      if (String.isBlank(objectName)) return refMap;
      
      Map<String, Object> untyped = describeSObject(sessionId, instanceUrl, objectName);
      if (untyped == null) return refMap;

      List<Object> fields = (List<Object>) untyped.get('fields');
      if (fields != null) {
        for (Object fieldObj : fields) {
          Map<String, Object> field = (Map<String, Object>) fieldObj;
          String fieldType = (String) field.get('type');
          List<Object> referenceTo = (List<Object>) field.get('referenceTo');
          Boolean createable = (Boolean) field.get('createable');
          
          if (fieldType == 'reference' && referenceTo != null && !referenceTo.isEmpty() && createable == true) {
             String fname = (String) field.get('name');
             // Take the first reference type (polymorphic fields might have multiple, usually we care about the primary or handle broadly)
             // For simplicity, taking the first one is standard for simple lookups. 
             // Polymorphic handling might require more complex logic later.
             String parent = (String) referenceTo[0]; 
             refMap.put(fname, parent);
          }
        }
      }
    } catch (Exception e) {
      System.debug('getReferenceFields Error: ' + e.getMessage());
    }
    return refMap;
  }
}

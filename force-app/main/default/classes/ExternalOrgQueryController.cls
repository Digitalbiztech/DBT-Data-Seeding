public with sharing class ExternalOrgQueryController {
    // Controller to authenticate to another Salesforce org via SOAP login
    // and run SOQL via REST, returning results to a Lightning Web Component.

    public class LoginResult {
        @AuraEnabled public String sessionId;
        @AuraEnabled public String serverUrl;
    }

    public class QueryResultWrapper {
        @AuraEnabled public Integer totalSize;
        @AuraEnabled public Boolean done;
        @AuraEnabled public List<String> columns;
        @AuraEnabled public List<Map<String, Object>> rows;
        @AuraEnabled public String nextRecordsUrl;
    }

    public class ConnectionTestResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String instanceUrl;
        @AuraEnabled public String apiVersion;
        @AuraEnabled public String sessionId;
    }

    // Cache for describe results within a single transaction to reduce callouts
    private static Map<String, Map<String, Object>> describeCache = new Map<String, Map<String, Object>>();

    public class DependencyNode {
        @AuraEnabled public String objectName;
        @AuraEnabled public String fieldName;
        @AuraEnabled public String relationshipType; // 'Lookup' or 'MasterDetail'
        @AuraEnabled public List<DependencyNode> parents;
        @AuraEnabled public List<DependencyNode> children;
        @AuraEnabled public Boolean isRequired;
        
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

    @AuraEnabled(cacheable=false)
    public static QueryResultWrapper loginAndQuery(String username, String password, String environment, String soql) {
        System.debug('ExternalOrgQueryController.loginAndQuery invoked. Username=' + username + ', Env=' + environment);
        try {
            if (String.isBlank(username) || String.isBlank(password) || String.isBlank(environment) || String.isBlank(soql)) {
                throw new CalloutException('All inputs (username, password, environment, soql) are required.');
            }

            LoginResult loginResult = login(username, password, environment);

            HttpRequest request = new HttpRequest();
            request.setMethod('GET');

            String soapServerUrl = loginResult.serverUrl; 
            Integer idx = soapServerUrl.indexOf('/services/Soap');
            if (idx <= 0) {
                throw new CalloutException('Unexpected serverUrl in login response: ' + soapServerUrl);
            }
            String hostBase = soapServerUrl.substring(0, idx);
            String endpoint = hostBase + '/services/data/v62.0/query?q=' + EncodingUtil.urlEncode(soql, 'UTF-8');
            request.setEndpoint(endpoint);
            request.setHeader('Authorization', 'Bearer ' + loginResult.sessionId);
            request.setHeader('Content-Type', 'application/json');

            Http http = new Http();
            System.debug('Sending REST query callout to: ' + endpoint);
            HTTPResponse response = http.send(request);
            System.debug('REST query response code: ' + response.getStatusCode());

            if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
                throw new CalloutException('Query failed: ' + response.getStatus() + ' ' + response.getBody());
            }

            Map<String, Object> untyped = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            QueryResultWrapper resultWrapper = new QueryResultWrapper();
            resultWrapper.totalSize = (Integer) untyped.get('totalSize');
            resultWrapper.done = (Boolean) untyped.get('done');
            resultWrapper.nextRecordsUrl = (String) untyped.get('nextRecordsUrl');

            List<Object> rawRecords = (List<Object>) untyped.get('records');
            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            List<String> columns = new List<String>();
            if (rawRecords != null) {
                System.debug('Raw records size: ' + rawRecords.size());
                Map<String, Boolean> seenColumns = new Map<String, Boolean>();
                for (Integer i = 0; i < rawRecords.size(); i++) {
                    Map<String, Object> rec = (Map<String, Object>) rawRecords[i];
                    if (rec == null) continue;
                    rec.remove('attributes');
                    rows.add(rec);
                    
                    // Collect columns from records
                    for (String k : rec.keySet()) {
                        if (!seenColumns.containsKey(k)) {
                            columns.add(k);
                            seenColumns.put(k, true);
                        }
                    }
                }
            }

            // Move Id to the front if present
            Boolean hasId = false;
            for (String c : columns) {
                if (c == 'Id') { hasId = true; break; }
            }
            if (hasId && (columns.isEmpty() == false)) {
                List<String> reordered = new List<String>();
                reordered.add('Id');
                for (String c : columns) {
                    if (c != 'Id') reordered.add(c);
                }
                columns = reordered;
            }

            resultWrapper.columns = columns;
            resultWrapper.rows = rows;
            return resultWrapper;

        } catch (Exception e) {
            System.debug('loginAndQuery Error: ' + e.getMessage() + ' Stack: ' + e.getStackTraceString());
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    @AuraEnabled(cacheable=false)
    public static ConnectionTestResult testConnection(String username, String password, String environment) {
        System.debug('ExternalOrgQueryController.testConnection invoked. Username=' + username + ', Env=' + environment);
        ConnectionTestResult res = new ConnectionTestResult();
        
        try {
            if (String.isBlank(username) || String.isBlank(password) || String.isBlank(environment)) {
                throw new CalloutException('Username, password, and environment are required.');
            }
            
            LoginResult loginResult = login(username, password, environment);
            Integer idx = loginResult.serverUrl.indexOf('/services/Soap');
            String hostBase = idx > 0 ? loginResult.serverUrl.substring(0, idx) : loginResult.serverUrl;
            
            res.success = true;
            res.message = 'Login successful';
            res.instanceUrl = hostBase;
            res.apiVersion = '62.0';
            res.sessionId = loginResult.sessionId;
            return res;
        } catch (Exception e) {
            System.debug('testConnection Error: ' + e.getMessage() + ' Stack: ' + e.getStackTraceString());
            res.success = false;
            res.message = e.getMessage();
            return res;
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<String> getAvailableObjects(String sessionId, String instanceUrl) {
        System.debug('ExternalOrgQueryController.getAvailableObjects invoked');
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
                throw new CalloutException('Failed to get objects: ' + response.getStatus() + ' ' + response.getBody());
            }

            Map<String, Object> untyped = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
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

    @AuraEnabled(cacheable=false)
    public static DependencyNode getObjectDependencies(String sessionId, String instanceUrl, String objectName, Integer maxDepth, List<String> excludedObjects) {
        System.debug('ExternalOrgQueryController.getObjectDependencies invoked for: ' + objectName);
        try {
            if (String.isBlank(sessionId) || String.isBlank(instanceUrl) || String.isBlank(objectName)) {
                throw new CalloutException('SessionId, instanceUrl, and objectName are required.');
            }

            // Set defaults if not provided
            if (maxDepth == null || maxDepth <= 0) {
                maxDepth = 3;
            }
            if (excludedObjects == null) {
                excludedObjects = new List<String>();
            }
            
            Set<String> excludedSet = new Set<String>(excludedObjects);
            
            // 1. Pre-fetch metadata using BFS and Composite API to avoid N+1 callouts
            prefetchMetadata(sessionId, instanceUrl, objectName, maxDepth, excludedSet);

            // 2. Build tree from cache (no callouts)
            Set<String> visited = new Set<String>();
            return buildDependencyTree(sessionId, instanceUrl, objectName, visited, maxDepth, excludedSet, 0);

        } catch (Exception e) {
            System.debug('getObjectDependencies Error: ' + e.getMessage());
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    private static void prefetchMetadata(String sessionId, String instanceUrl, String rootObject, Integer maxDepth, Set<String> excludedObjects) {
        Set<String> currentLevel = new Set<String>{rootObject};
        Set<String> visited = new Set<String>();
        Set<String> allToDescribe = new Set<String>();

        // BFS to collect all objects that need description
        for (Integer depth = 0; depth <= maxDepth; depth++) {
            Set<String> nextLevel = new Set<String>();
            Set<String> neededDescriptions = new Set<String>();

            for (String obj : currentLevel) {
                if (visited.contains(obj) || excludedObjects.contains(obj)) continue;
                visited.add(obj);
                if (!describeCache.containsKey(obj)) {
                    neededDescriptions.add(obj);
                } else {
                    // If already cached (e.g. from previous run), we still need to parse it to find next level
                    collectParents(describeCache.get(obj), nextLevel, excludedObjects);
                }
            }

            if (!neededDescriptions.isEmpty()) {
                // Batch describe the needed objects
                executeBatchDescribe(sessionId, instanceUrl, neededDescriptions);
                
                // After describing, parse them to find the next level of parents
                for (String obj : neededDescriptions) {
                    Map<String, Object> description = describeCache.get(obj);
                    collectParents(description, nextLevel, excludedObjects);
                }
            }
            
            if (nextLevel.isEmpty()) break;
            currentLevel = nextLevel;
        }
    }

    private static void collectParents(Map<String, Object> description, Set<String> nextLevel, Set<String> excludedObjects) {
        if (description == null) return;
        List<Object> fields = (List<Object>) description.get('fields');
        if (fields != null) {
            for (Object fieldObj : fields) {
                Map<String, Object> field = (Map<String, Object>) fieldObj;
                String fieldType = (String) field.get('type');
                List<Object> referenceTo = (List<Object>) field.get('referenceTo');
                Boolean createable = (Boolean) field.get('createable');
                
                if (fieldType == 'reference' && referenceTo != null && createable == true) {
                    for (Object ref : referenceTo) {
                        String parentName = (String) ref;
                        if (!excludedObjects.contains(parentName)) {
                            nextLevel.add(parentName);
                        }
                    }
                }
            }
        }
    }

    private static void executeBatchDescribe(String sessionId, String instanceUrl, Set<String> objectNames) {
        System.debug('Executing batch describe for ' + objectNames.size() + ' objects.');
        List<String> batch = new List<String>();
        for (String obj : objectNames) {
            batch.add(obj);
            if (batch.size() == 25) { // Composite subrequest limit
                sendBatchRequest(sessionId, instanceUrl, batch);
                batch.clear();
            }
        }
        if (!batch.isEmpty()) {
            sendBatchRequest(sessionId, instanceUrl, batch);
        }
    }

    private static void sendBatchRequest(String sessionId, String instanceUrl, List<String> objectNames) {
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
            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            List<Object> results = (List<Object>) responseBody.get('results');
            if (results != null) {
                for (Object resObj : results) {
                    Map<String, Object> res = (Map<String, Object>) resObj;
                    Integer statusCode = (Integer) res.get('statusCode');
                    String refId = (String) res.get('referenceId'); // This is the object name
                    
                    if (statusCode >= 200 && statusCode < 300) {
                        Map<String, Object> result = (Map<String, Object>) res.get('result');
                        describeCache.put(refId, result);
                    } else {
                        System.debug('Failed to describe ' + refId + ' in batch: ' + res.get('result'));
                        describeCache.put(refId, null); // Prevent retry
                    }
                }
            }
        } else {
            System.debug('Batch describe callout failed: ' + response.getStatus());
        }
    }

    private static DependencyNode buildDependencyTree(String sessionId, String instanceUrl, String objectName, Set<String> visited, Integer maxDepth, Set<String> excludedObjects, Integer currentDepth) {
        // Avoid circular dependencies
        if (visited.contains(objectName)) {
            return null;
        }
        
        // Check depth limit
        if (currentDepth >= maxDepth) {
            return null;
        }
        
        // Check if object is excluded
        if (excludedObjects.contains(objectName)) {
            return null;
        }
        
        visited.add(objectName);

        DependencyNode rootNode = new DependencyNode();
        rootNode.objectName = objectName;
        rootNode.fieldName = '';

        try {
            // This will now hit the cache populated by prefetchMetadata
            Map<String, Object> untyped = describeSObject(sessionId, instanceUrl, objectName);
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
                    
                    // Check if this is a lookup or master-detail relationship
                    if (fieldType == 'reference' && String.isNotBlank(relationshipName) && referenceTo != null && !referenceTo.isEmpty() && createable != null && createable) {
                        String fieldName = (String) field.get('name');
                        
                        // Handle polymorphic fields by iterating over all referenced objects
                        for (Object ref : referenceTo) {
                            String parentObjectName = (String) ref;
                            if (excludedObjects.contains(parentObjectName)) continue;

                            System.debug('Adding dependency for: ' + objectName + ' -> ' + relationshipName + ' (' + parentObjectName + ')');
                            
                            DependencyNode parentNode = new DependencyNode(parentObjectName, fieldName);
                            parentNode.relationshipType = 'Lookup';
                            // Required if non-nillable and not defaulted on create
                            parentNode.isRequired = (nillable == false) && (defaultedOnCreate != true);
                            
                            // Recursively get parent dependencies with depth control
                            // Since we prefetched, these calls won't make new HTTP requests
                            DependencyNode parentTree = buildDependencyTree(sessionId, instanceUrl, parentObjectName, visited, maxDepth, excludedObjects, currentDepth + 1);
                            if (parentTree != null) {
                                parentNode.parents = parentTree.parents;
                                parentNode.children = parentTree.children;
                            }
                            
                            rootNode.parents.add(parentNode);
                        }
                    }
                }
            }

            // Add child relationships (objects that reference this object)
            if (childRels != null) {
                for (Object crObj : childRels) {
                    Map<String, Object> cr = (Map<String, Object>) crObj;
                    String childSObject = (String) cr.get('childSObject');
                    String childField = (String) cr.get('field');
                    if (String.isBlank(childSObject) || String.isBlank(childField)) continue;
                    if (excludedObjects.contains(childSObject)) continue;

                    DependencyNode childNode = new DependencyNode(childSObject, childField);
                    childNode.relationshipType = 'Child';
                    rootNode.children.add(childNode);
                }
            }
        } catch (Exception e) {
            System.debug('Error building dependency tree for ' + objectName + ': ' + e.getMessage());
        }

        visited.remove(objectName);
        return rootNode;
    }

    // Describe helper with simple cache to avoid blowing callout limits
    private static Map<String, Object> describeSObject(String sessionId, String instanceUrl, String objectName) {
        if (String.isBlank(objectName)) return null;
        if (describeCache.containsKey(objectName)) {
            return describeCache.get(objectName);
        }

        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setEndpoint(instanceUrl + '/services/data/v62.0/sobjects/' + objectName + '/describe/');
        request.setHeader('Authorization', 'Bearer ' + sessionId);
        request.setHeader('Content-Type', 'application/json');

        Http http = new Http();
        HTTPResponse response = http.send(request);

        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            System.debug('Failed to describe object ' + objectName + ': ' + response.getStatus());
            describeCache.put(objectName, null);
            return null;
        }

        Map<String, Object> untyped = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        describeCache.put(objectName, untyped);
        return untyped;
    }

    @AuraEnabled(cacheable=false)
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
                if (String.isBlank(objectName)) {
                    continue;
                }
                Map<String, Object> describeResult = describeSObject(sessionId, instanceUrl, objectName);
                if (describeResult == null) {
                    continue;
                }
                List<String> creatableFields = new List<String>();
                List<Object> fields = (List<Object>) describeResult.get('fields');
                if (fields != null) {
                    for (Object fieldObj : fields) {
                        Map<String, Object> field = (Map<String, Object>) fieldObj;
                        Boolean createable = (Boolean) field.get('createable');
                        Boolean defaultedOnCreate = (Boolean) field.get('defaultedOnCreate');
                        if (createable == null || !createable || defaultedOnCreate == null || defaultedOnCreate) {
                            continue;
                        }
                        String fieldName = (String) field.get('name');
                        if (String.isNotBlank(fieldName)) {
                            creatableFields.add(fieldName);
                        }
                    }
                }
                creatableFields.sort();
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

    @AuraEnabled(cacheable=false)
    public static QueryResultWrapper queryWithSession(String sessionId, String instanceUrl, String soql) {
        System.debug('queryWithSession invoked. SOQL: ' + soql);
        try {
            if (String.isBlank(sessionId) || String.isBlank(instanceUrl) || String.isBlank(soql)) {
                throw new CalloutException('SessionId, instanceUrl, and soql are required.');
            }

            HttpRequest request = new HttpRequest();
            request.setMethod('GET');
            String endpoint = instanceUrl + '/services/data/v62.0/query?q=' + EncodingUtil.urlEncode(soql, 'UTF-8');
            request.setEndpoint(endpoint);
            request.setHeader('Authorization', 'Bearer ' + sessionId);
            request.setHeader('Content-Type', 'application/json');

            Http http = new Http();
            HTTPResponse response = http.send(request);

            if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
                throw new CalloutException('Query failed: ' + response.getStatus() + ' ' + response.getBody());
            }

            Map<String, Object> untyped = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            QueryResultWrapper resultWrapper = new QueryResultWrapper();
            resultWrapper.totalSize = (Integer) untyped.get('totalSize');
            resultWrapper.done = (Boolean) untyped.get('done');
            resultWrapper.nextRecordsUrl = (String) untyped.get('nextRecordsUrl');

            List<Object> rawRecords = (List<Object>) untyped.get('records');
            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            List<String> columns = new List<String>();
            if (rawRecords != null) {
                Map<String, Boolean> seenColumns = new Map<String, Boolean>();
                for (Integer i = 0; i < rawRecords.size(); i++) {
                    Map<String, Object> rec = (Map<String, Object>) rawRecords[i];
                    if (rec == null) continue;
                    rec.remove('attributes');
                    rows.add(rec);
                    if (i == 0) {
                        for (String k : rec.keySet()) {
                            if (!seenColumns.containsKey(k)) {
                                columns.add(k);
                                seenColumns.put(k, true);
                            }
                        }
                    } else {
                        for (String k : rec.keySet()) {
                            if (!seenColumns.containsKey(k)) {
                                columns.add(k);
                                seenColumns.put(k, true);
                            }
                        }
                    }
                }
            }

            resultWrapper.columns = columns;
            resultWrapper.rows = rows;
            return resultWrapper;
        } catch (Exception e) {
             System.debug('queryWithSession Error: ' + e.getMessage());
             AuraHandledException ahe = new AuraHandledException(e.getMessage());
             ahe.setMessage(e.getMessage());
             throw ahe;
        }
    }

    private static LoginResult login(String username, String password, String environment) {
        String loginHost = (environment == 'Sandbox') ? 'https://test.salesforce.com' : 'https://login.salesforce.com';
        System.debug('Preparing SOAP login callout to host: ' + loginHost);
        String loginEndpoint = loginHost + '/services/Soap/u/62.0';

        String soapEnvelope =
            '<?xml version="1.0" encoding="utf-8"?>' +
            '<env:Envelope xmlns:xsd="http://www.w3.org/2001/XMLSchema" ' +
                'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
                'xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">' +
                '<env:Body>' +
                    '<n1:login xmlns:n1="urn:partner.soap.sforce.com">' +
                        '<n1:username>' + xmlEscape(username) + '</n1:username>' +
                        '<n1:password>' + xmlEscape(password) + '</n1:password>' +
                    '</n1:login>' +
                '</env:Body>' +
            '</env:Envelope>';

        HttpRequest request = new HttpRequest();
        request.setEndpoint(loginEndpoint);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        request.setHeader('SOAPAction', 'login');
        request.setBody(soapEnvelope);

        Http http = new Http();
        System.debug('Sending SOAP login callout to: ' + loginEndpoint);
        HTTPResponse response = http.send(request);
        
        System.debug('Login response code: ' + response.getStatusCode());

        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            String msg = 'Login failed: ' + response.getStatus() + ' ' + response.getBody();
            System.debug(msg);
            throw new CalloutException(msg);
        }

        Dom.Document doc = new Dom.Document();
        doc.load(response.getBody());

        Dom.XMLNode envelope = doc.getRootElement();
        Dom.XMLNode body = envelope.getChildElement('Body', 'http://schemas.xmlsoap.org/soap/envelope/');
        if (body == null) {
            throw new CalloutException('Invalid SOAP response: missing Body');
        }
        Dom.XMLNode loginResponse = body.getChildElement('loginResponse', 'urn:partner.soap.sforce.com');
        if (loginResponse == null) {
            Dom.XMLNode fault = body.getChildElement('Fault', 'http://schemas.xmlsoap.org/soap/envelope/');
            if (fault != null) {
                String faultText = fault.getText();
                throw new CalloutException('Login fault' + (String.isBlank(faultText) ? '' : (': ' + faultText)));
            }
            throw new CalloutException('Invalid SOAP response: missing loginResponse');
        }
        Dom.XMLNode resultNode = loginResponse.getChildElement('result', 'urn:partner.soap.sforce.com');
        if (resultNode == null) {
            throw new CalloutException('Invalid SOAP response: missing result');
        }

        String sessionId = safeGetText(resultNode, 'sessionId');
        String serverUrl = safeGetText(resultNode, 'serverUrl');
        if (String.isBlank(sessionId) || String.isBlank(serverUrl)) {
            throw new CalloutException('Login response missing sessionId or serverUrl');
        }

        LoginResult loginResult = new LoginResult();
        loginResult.sessionId = sessionId;
        loginResult.serverUrl = serverUrl;
        return loginResult;
    }

    private static String safeGetText(Dom.XMLNode parent, String childLocalName) {
        Dom.XMLNode child = parent.getChildElement(childLocalName, 'urn:partner.soap.sforce.com');
        return child == null ? null : child.getText();
    }
    
    private static String xmlEscape(String input) {
        if (input == null) {
            return '';
        }
        String s = input;
        s = s.replace('&', '&amp;');
        s = s.replace('<', '&lt;');
        s = s.replace('>', '&gt;');
        s = s.replace('"', '&quot;');
        // Avoid literal single quote in replacement to bypass tooling issues with escaping
        s = s.replace(String.fromCharArray(new List<Integer>{39}), '&apos;');
        return s;
    }
    // =====================
    // Current-org operations
    // =====================
    @AuraEnabled(cacheable=false)
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

    @AuraEnabled(cacheable=false)
    public static QueryResultWrapper queryCurrent(String soql) {
        if (String.isBlank(soql)) {
            AuraHandledException ahe = new AuraHandledException('SOQL is required.');
            ahe.setMessage('SOQL is required.');
            throw ahe;
        }
        try {
            List<SObject> recs = Database.query(soql);
            QueryResultWrapper wrap = new QueryResultWrapper();
            wrap.totalSize = recs.size();
            wrap.done = true;
            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            Set<String> allCols = new Set<String>();
            for (SObject s : recs) {
                Map<String, Object> row = new Map<String, Object>();
                Map<String, Object> fields = s.getPopulatedFieldsAsMap();
                for (String k : fields.keySet()) {
                    row.put(k, fields.get(k));
                    allCols.add(k);
                }
                rows.add(row);
            }
            List<String> columns = new List<String>(allCols);
            // Move Id to front if present
            Boolean hasId = false;
            for (String c : columns) { if (c == 'Id') { hasId = true; break; } }
            if (hasId && !columns.isEmpty()) {
                List<String> reordered = new List<String>();
                reordered.add('Id');
                for (String c : columns) { if (c != 'Id') reordered.add(c); }
                columns = reordered;
            }
            wrap.columns = columns;
            wrap.rows = rows;
            return wrap;
        } catch (Exception e) {
            System.debug('queryCurrent Error: ' + e.getMessage());
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    @AuraEnabled(cacheable=false)
    public static DependencyNode getObjectDependenciesCurrent(String objectName, Integer maxDepth, List<String> excludedObjects) {
        try {
            if (String.isBlank(objectName)) {
                throw new CalloutException('objectName is required.');
            }
            if (maxDepth == null || maxDepth < 0) maxDepth = 0;
            if (excludedObjects == null) excludedObjects = new List<String>();
            Set<String> visited = new Set<String>();
            Set<String> excluded = new Set<String>(excludedObjects);
            return buildDependencyTreeCurrent(objectName, visited, maxDepth, excluded, 0);
        } catch (Exception e) {
            System.debug('getObjectDependenciesCurrent Error: ' + e.getMessage());
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    private static DependencyNode buildDependencyTreeCurrent(String objectName, Set<String> visited, Integer maxDepth, Set<String> excluded, Integer currentDepth) {
        DependencyNode root = new DependencyNode();
        root.objectName = objectName;
        root.fieldName = '';

        if (visited.contains(objectName)) return root;
        visited.add(objectName);

        try {
            Schema.SObjectType t = Schema.getGlobalDescribe().get(objectName);
            if (t == null) return root;
            Schema.DescribeSObjectResult d = t.getDescribe();

            // Only add parents if within depth
            if (currentDepth < maxDepth) {
                for (Schema.SObjectField f : d.fields.getMap().values()) {
                    Schema.DescribeFieldResult fd = f.getDescribe();
                    if (fd.getType() == Schema.DisplayType.Reference && String.isNotBlank(fd.getRelationshipName())) {
                        List<Schema.SObjectType> rTo = fd.getReferenceTo();
                        if (rTo != null && !rTo.isEmpty() && fd.isCreateable() && !fd.isDefaultedOnCreate()) {
                            String parentName = rTo[0].getDescribe().getName();
                            if (!excluded.contains(parentName)) {
                                DependencyNode parentNode = new DependencyNode(parentName, fd.getName());
                                parentNode.relationshipType = 'Lookup';
                                parentNode.isRequired = (!fd.isNillable()) && (!fd.isDefaultedOnCreate());
                                DependencyNode parentTree = buildDependencyTreeCurrent(parentName, visited, maxDepth, excluded, currentDepth + 1);
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

            // Always include immediate child relationships list (not recursing downwards here)
            for (Schema.ChildRelationship cr : d.getChildRelationships()) {
                String childName = cr.getChildSObject() != null ? cr.getChildSObject().getDescribe().getName() : null;
                String fieldName = cr.getField() != null ? cr.getField().getDescribe().getName() : null;
                if (String.isBlank(childName) || String.isBlank(fieldName)) continue;
                if (excluded.contains(childName)) continue;
                DependencyNode childNode = new DependencyNode(childName, fieldName);
                childNode.relationshipType = 'Child';
                root.children.add(childNode);
            }
        } catch (Exception e) {
            System.debug('Error building current-org dependency tree for ' + objectName + ': ' + e.getMessage());
        }

        visited.remove(objectName);
        return root;
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, List<String>> getCreateableFieldsCurrent(List<String> objectNames) {
        Map<String, List<String>> out = new Map<String, List<String>>();
        if (objectNames == null) return out;
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        for (String name : objectNames) {
            if (String.isBlank(name)) continue;
            Schema.SObjectType t = gd.get(name);
            if (t == null) { out.put(name, new List<String>()); continue; }
            Schema.DescribeSObjectResult d = t.getDescribe();
            List<String> fields = new List<String>();
            for (Schema.SObjectField f : d.fields.getMap().values()) {
                Schema.DescribeFieldResult fd = f.getDescribe();
                if (fd.isCreateable() && !fd.isDefaultedOnCreate()) {
                    fields.add(fd.getName());
                }
            }
            fields.sort();
            out.put(name, fields);
        }
        return out;
    }

    // Simple current-org insert support used by LWC Start Import
    public class InsertMapping {
        @AuraEnabled public String oldId;
        @AuraEnabled public String newId;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String name;
        @AuraEnabled public String recordUrl;
    }

    @AuraEnabled(cacheable=false)
    public static String getBatchReport(String jobId) {
        if (String.isBlank(jobId)) return null;
        try {
            // Find the file created by the batch
            String title = 'SeedingReport_' + jobId;
            List<ContentVersion> cvs = [SELECT VersionData FROM ContentVersion WHERE Title = :title AND IsLatest = true LIMIT 1];
            if (!cvs.isEmpty()) {
                return cvs[0].VersionData.toString();
            }
        } catch (Exception e) {
            System.debug('Error retrieving batch report: ' + e.getMessage());
        }
        return null;
    }

    @AuraEnabled(cacheable=false)
    public static List<InsertMapping> insertRecordsCurrent(String objectName, List<Map<String, Object>> records) {
        try {
            if (String.isBlank(objectName)) {
                throw new CalloutException('objectName is required');
            }
            List<InsertMapping> out = new List<InsertMapping>();
            if (records == null || records.isEmpty()) {
                return out;
            }
            Schema.SObjectType t = Schema.getGlobalDescribe().get(objectName);
            if (t == null) {
                throw new CalloutException('Unknown sObject: ' + objectName);
            }
            List<SObject> toInsert = new List<SObject>();
            List<String> oldIds = new List<String>();
            List<String> inputNames = new List<String>();

            for (Map<String, Object> rec : records) {
                if (rec == null) continue;
                SObject sobj = t.newSObject();
                String oldId = (rec.containsKey('Id') && rec.get('Id') != null) ? String.valueOf(rec.get('Id')) : null;
                oldIds.add(oldId);
                
                String recName = (rec.containsKey('Name')) ? String.valueOf(rec.get('Name')) : oldId;
                inputNames.add(recName);

                for (String key : rec.keySet()) {
                    if (key == 'Id') continue; // never attempt to set Id on insert
                    try {
                        sobj.put(key, rec.get(key));
                    } catch (Exception e) {
                        // Ignore fields that do not exist or cannot be set
                    }
                }
                toInsert.add(sobj);
            }
            Database.SaveResult[] results = Database.insert(toInsert, false);
            String baseUrl = URL.getOrgDomainUrl().toExternalForm();

            for (Integer i = 0; i < results.size(); i++) {
                InsertMapping m = new InsertMapping();
                m.oldId = i < oldIds.size() ? oldIds[i] : null;
                m.name = i < inputNames.size() ? inputNames[i] : null;
                
                Database.SaveResult sr = results[i];
                if (sr.isSuccess()) {
                    m.success = true;
                    m.newId = (String) sr.getId();
                    m.recordUrl = baseUrl + '/' + m.newId;
                } else {
                    m.success = false;
                    if (sr.getErrors() != null && sr.getErrors().size() > 0) {
                        m.errorMessage = sr.getErrors()[0].getMessage();
                    } else {
                        m.errorMessage = 'Unknown DML error';
                    }
                }
                out.add(m);
            }
            return out;
        } catch (Exception e) {
            System.debug('insertRecordsCurrent Error: ' + e.getMessage());
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<InsertMapping> updateRecordsCurrent(String objectName, List<Map<String, Object>> records) {
        try {
            if (String.isBlank(objectName)) {
                throw new CalloutException('objectName is required');
            }
            List<InsertMapping> out = new List<InsertMapping>();
            if (records == null || records.isEmpty()) {
                return out;
            }
            Schema.SObjectType t = Schema.getGlobalDescribe().get(objectName);
            if (t == null) {
                throw new CalloutException('Unknown sObject: ' + objectName);
            }
            List<SObject> toUpdate = new List<SObject>();
            List<String> targetIds = new List<String>();
            List<String> inputNames = new List<String>();

            for (Map<String, Object> rec : records) {
                if (rec == null) continue;
                SObject sobj = t.newSObject();
                String targetId = (rec.containsKey('Id') && rec.get('Id') != null) ? String.valueOf(rec.get('Id')) : null;
                if (String.isBlank(targetId)) {
                    continue; 
                }
                targetIds.add(targetId);
                String recName = (rec.containsKey('Name')) ? String.valueOf(rec.get('Name')) : targetId;
                inputNames.add(recName);
                
                for (String key : rec.keySet()) {
                    try {
                        sobj.put(key, rec.get(key));
                    } catch (Exception e) {
                        // Ignore
                    }
                }
                toUpdate.add(sobj);
            }
            
            if (toUpdate.isEmpty()) {
                return out;
            }

            Database.SaveResult[] results = Database.update(toUpdate, false);
            String baseUrl = URL.getOrgDomainUrl().toExternalForm();

            for (Integer i = 0; i < results.size(); i++) {
                InsertMapping m = new InsertMapping();
                m.oldId = i < targetIds.size() ? targetIds[i] : null; 
                m.name = i < inputNames.size() ? inputNames[i] : null;

                Database.SaveResult sr = results[i];
                if (sr.isSuccess()) {
                    m.success = true;
                    m.newId = (String) sr.getId();
                    m.recordUrl = baseUrl + '/' + m.newId;
                } else {
                    m.success = false;
                    if (sr.getErrors() != null && sr.getErrors().size() > 0) {
                        m.errorMessage = sr.getErrors()[0].getMessage();
                    } else {
                        m.errorMessage = 'Unknown DML error';
                    }
                }
                out.add(m);
            }
            return out;
        } catch (Exception e) {
            System.debug('updateRecordsCurrent Error: ' + e.getMessage());
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    // =====================
    // Remote (REST) Write Operations
    // =====================

    @AuraEnabled(cacheable=false)
    public static List<InsertMapping> createRecordsRemote(String sessionId, String instanceUrl, String objectName, List<Map<String, Object>> records) {
        return executeRemoteComposite(sessionId, instanceUrl, objectName, records, 'POST');
    }

    @AuraEnabled(cacheable=false)
    public static List<InsertMapping> updateRecordsRemote(String sessionId, String instanceUrl, String objectName, List<Map<String, Object>> records) {
        return executeRemoteComposite(sessionId, instanceUrl, objectName, records, 'PATCH');
    }

    public class MatchResult {
        @AuraEnabled public String sourceId;
        @AuraEnabled public String destId;
    }

    @AuraEnabled(cacheable=false)
    public static List<MatchResult> findMatchingRecords(
        String sessionId, 
        String instanceUrl, 
        String objectName, 
        List<String> matchFields, 
        List<Map<String, Object>> sourceRecords
    ) {
        List<MatchResult> results = new List<MatchResult>();
        try {
            if (sourceRecords == null || sourceRecords.isEmpty() || matchFields == null || matchFields.isEmpty()) {
                return results;
            }

            // 1. Collect values for filtering
            // Map<FieldName, Set<Value>>
            Map<String, Set<String>> fieldValues = new Map<String, Set<String>>();
            for (String f : matchFields) {
                fieldValues.put(f, new Set<String>());
            }

            for (Map<String, Object> row : sourceRecords) {
                for (String f : matchFields) {
                    Object val = row.get(f);
                    if (val != null) {
                        fieldValues.get(f).add(String.valueOf(val));
                    }
                }
            }

            // 2. Build Query
            // "SELECT Id, Name, Email FROM Contact WHERE Name IN :names AND Email IN :emails"
            String selectClause = 'Id, ' + String.join(matchFields, ', ');
            String whereClause = '';
            
            for (String f : matchFields) {
                Set<String> vals = fieldValues.get(f);
                if (vals.isEmpty()) continue;
                
                // For query construction, we need to escape and format. 
                // Note: Large lists might hit query length limits, so caller should chunk sourceRecords (e.g. 200 at a time).
                List<String> quoted = new List<String>();
                String quote = String.fromCharArray(new List<Integer>{39});
                for (String v : vals) {
                    quoted.add(quote + String.escapeSingleQuotes(v) + quote);
                }
                
                if (whereClause.length() > 0) whereClause += ' AND ';
                whereClause += f + ' IN (' + String.join(quoted, ',') + ')';
            }

            if (String.isBlank(whereClause)) {
                // No filterable values found (all nulls?), return empty or risk full table scan (unsafe)
                return results;
            }

            String soql = 'SELECT ' + selectClause + ' FROM ' + objectName + ' WHERE ' + whereClause + ' LIMIT 10000';
            
            // 3. Execute Query
            List<Map<String, Object>> destRows = new List<Map<String, Object>>();
            
            if (String.isNotBlank(sessionId) && String.isNotBlank(instanceUrl)) {
                // Remote
                QueryResultWrapper qr = queryWithSession(sessionId, instanceUrl, soql);
                if (qr != null && qr.rows != null) {
                    destRows = qr.rows;
                }
            } else {
                // Local
                for (SObject s : Database.query(soql)) {
                    Map<String, Object> r = new Map<String, Object>();
                    r.put('Id', s.Id);
                    for (String f : matchFields) {
                        // Handle potential relation traversal like 'Parent.Name' if needed, 
                        // but for now assume flat fields as per UI
                        try {
                            r.put(f, s.get(f));
                        } catch (Exception e) { /* ignore */ }
                    }
                    destRows.add(r);
                }
            }

            // 4. In-Memory Match
            // Build map of Key -> DestId
            // Key logic: join values with pipe or similar. Handle nulls.
            Map<String, String> destMap = new Map<String, String>();
            for (Map<String, Object> d : destRows) {
                String key = generateCompositeKey(d, matchFields);
                if (!destMap.containsKey(key)) {
                    destMap.put(key, (String) d.get('Id'));
                }
            }

            // 5. Match Source
            for (Map<String, Object> s : sourceRecords) {
                String key = generateCompositeKey(s, matchFields);
                if (destMap.containsKey(key)) {
                    MatchResult mr = new MatchResult();
                    mr.sourceId = (String) s.get('Id');
                    mr.destId = destMap.get(key);
                    results.add(mr);
                }
            }

            return results;
        } catch (Exception e) {
            System.debug('findMatchingRecords Error: ' + e.getMessage());
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    private static String generateCompositeKey(Map<String, Object> record, List<String> fields) {
        List<String> parts = new List<String>();
        for (String f : fields) {
            Object v = record.get(f);
            parts.add(v == null ? '' : String.valueOf(v));
        }
        return String.join(parts, '|');
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
        try {
            DataSeedingBatch batch = new DataSeedingBatch(sourceSessionId, sourceInstanceUrl, destSessionId, destInstanceUrl, tasks, planEdges);
            return Database.executeBatch(batch, 1);
        } catch (Exception e) {
             System.debug('startDataSeedingBatch Error: ' + e.getMessage());
             AuraHandledException ahe = new AuraHandledException(e.getMessage());
             ahe.setMessage(e.getMessage());
             throw ahe;
        }
    }

    @AuraEnabled
    public static AsyncApexJob getBatchJobStatus(String jobId) {
        return [SELECT Id, Status, JobItemsProcessed, TotalJobItems, NumberOfErrors, ExtendedStatus FROM AsyncApexJob WHERE Id = :jobId];
    }

    private static List<InsertMapping> executeRemoteComposite(String sessionId, String instanceUrl, String objectName, List<Map<String, Object>> records, String method) {
        try {
            if (String.isBlank(sessionId) || String.isBlank(instanceUrl) || String.isBlank(objectName)) {
                throw new CalloutException('SessionId, InstanceUrl, and ObjectName are required.');
            }
            List<InsertMapping> out = new List<InsertMapping>();
            if (records == null || records.isEmpty()) return out;

            // Prepare request body: { "allOrNone": false, "records": [...] }
            // For REST, type attributes are usually handled automatically if structure is right, 
            // but explicit attributes {"type": "Account"} helps.
            List<Map<String, Object>> payloadRecords = new List<Map<String, Object>>();
            List<String> trackingIds = new List<String>(); // Track input IDs (if any) to map back to results
            List<String> inputNames = new List<String>();

            for (Map<String, Object> r : records) {
                Map<String, Object> rec = new Map<String, Object>(r);
                
                // For mapping results back:
                String tid = r.containsKey('Id') ? String.valueOf(r.get('Id')) : null;
                trackingIds.add(tid);
                
                String recName = (r.containsKey('Name')) ? String.valueOf(r.get('Name')) : tid;
                inputNames.add(recName);

                if (method == 'POST' && rec.containsKey('Id')) {
                    rec.remove('Id');
                }

                // Ensure attributes
                Map<String, String> attributes = new Map<String, String>{ 'type' => objectName };
                rec.put('attributes', attributes);
                payloadRecords.add(rec);
            }

            Map<String, Object> requestBody = new Map<String, Object>();
            requestBody.put('allOrNone', false);
            requestBody.put('records', payloadRecords);

            HttpRequest req = new HttpRequest();
            req.setMethod(method); // POST or PATCH
            req.setEndpoint(instanceUrl + '/services/data/v62.0/composite/sobjects');
            req.setHeader('Authorization', 'Bearer ' + sessionId);
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(requestBody));

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                // Response is List<Object> directly for composite/sobjects
                List<Object> results = (List<Object>) JSON.deserializeUntyped(res.getBody());
                for (Integer i = 0; i < results.size(); i++) {
                    Map<String, Object> result = (Map<String, Object>) results[i];
                    InsertMapping m = new InsertMapping();
                    m.oldId = (i < trackingIds.size()) ? trackingIds[i] : null;
                    m.name = (i < inputNames.size()) ? inputNames[i] : null;
                    Boolean success = (Boolean) result.get('success');
                    m.success = success;
                    if (success == true) {
                        m.newId = (String) result.get('id');
                        m.recordUrl = instanceUrl + '/' + m.newId;
                    } else {
                        List<Object> errors = (List<Object>) result.get('errors');
                        if (errors != null && !errors.isEmpty()) {
                            Map<String, Object> err = (Map<String, Object>) errors[0];
                            m.errorMessage = (String) err.get('message');
                        } else {
                            m.errorMessage = 'Unknown remote error';
                        }
                    }
                    out.add(m);
                }
            } else {
                throw new CalloutException('Remote ' + method + ' failed: ' + res.getStatus() + ' ' + res.getBody());
            }
            return out;
        } catch (Exception e) {
             System.debug('executeRemoteComposite Error: ' + e.getMessage());
             AuraHandledException ahe = new AuraHandledException(e.getMessage());
             ahe.setMessage(e.getMessage());
             throw ahe;
        }
    }
}
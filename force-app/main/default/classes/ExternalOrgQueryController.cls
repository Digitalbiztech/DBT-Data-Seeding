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
        if (String.isBlank(username) || String.isBlank(password) || String.isBlank(environment) || String.isBlank(soql)) {
            throw new AuraHandledException('All inputs (username, password, environment, soql) are required.');
        }

        System.debug('ExternalOrgQueryController.loginAndQuery invoked');
        LoginResult loginResult = login(username, password, environment);

        HttpRequest request = new HttpRequest();
        request.setMethod('GET');

        String soapServerUrl = loginResult.serverUrl; // e.g. https://yourInstance.my.salesforce.com/services/Soap/u/62.0/ORG
        Integer idx = soapServerUrl.indexOf('/services/Soap');
        if (idx <= 0) {
            throw new AuraHandledException('Unexpected serverUrl in login response.');
        }
        String hostBase = soapServerUrl.substring(0, idx);
        String endpoint = hostBase + '/services/data/v62.0/query?q=' + EncodingUtil.urlEncode(soql, 'UTF-8');
        request.setEndpoint(endpoint);
        request.setHeader('Authorization', 'Bearer ' + loginResult.sessionId);
        request.setHeader('Content-Type', 'application/json');

        Http http = new Http();
        System.debug('Sending REST query callout to: ' + endpoint);
        HTTPResponse response = http.send(request);

        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            throw new AuraHandledException('Query failed: ' + response.getStatus() + ' ' + response.getBody());
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
            // Build rows and derive columns primarily from the first record to preserve a stable order
            Map<String, Boolean> seenColumns = new Map<String, Boolean>();
            for (Integer i = 0; i < rawRecords.size(); i++) {
                Map<String, Object> rec = (Map<String, Object>) rawRecords[i];
                if (rec == null) {
                    continue;
                }
                rec.remove('attributes');
                rows.add(rec);
                // For the first record, capture the order of keys as provided
                if (i == 0) {
                    for (String k : rec.keySet()) {
                        if (!seenColumns.containsKey(k)) {
                            columns.add(k);
                            seenColumns.put(k, true);
                        }
                    }
                } else {
                    // For subsequent records, add any new columns not seen yet to the end
                    for (String k : rec.keySet()) {
                        if (!seenColumns.containsKey(k)) {
                            columns.add(k);
                            seenColumns.put(k, true);
                        }
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
    }

    @AuraEnabled(cacheable=false)
    public static ConnectionTestResult testConnection(String username, String password, String environment) {
        if (String.isBlank(username) || String.isBlank(password) || String.isBlank(environment)) {
            throw new AuraHandledException('Username, password, and environment are required.');
        }
        System.debug('ExternalOrgQueryController.testConnection invoked');
        try {
            LoginResult loginResult = login(username, password, environment);
            Integer idx = loginResult.serverUrl.indexOf('/services/Soap');
            String hostBase = idx > 0 ? loginResult.serverUrl.substring(0, idx) : loginResult.serverUrl;
            ConnectionTestResult res = new ConnectionTestResult();
            res.success = true;
            res.message = 'Login successful';
            res.instanceUrl = hostBase;
            res.apiVersion = '62.0';
            res.sessionId = loginResult.sessionId;
            return res;
        } catch (Exception e) {
            ConnectionTestResult res = new ConnectionTestResult();
            res.success = false;
            res.message = e.getMessage();
            return res;
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<String> getAvailableObjects(String sessionId, String instanceUrl) {
        if (String.isBlank(sessionId) || String.isBlank(instanceUrl)) {
            throw new AuraHandledException('SessionId and instanceUrl are required.');
        }

        System.debug('ExternalOrgQueryController.getAvailableObjects invoked');
        
        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setEndpoint(instanceUrl + '/services/data/v62.0/sobjects/');
        request.setHeader('Authorization', 'Bearer ' + sessionId);
        request.setHeader('Content-Type', 'application/json');

        Http http = new Http();
        System.debug('Sending REST callout to: ' + request.getEndpoint());
        HTTPResponse response = http.send(request);

        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            throw new AuraHandledException('Failed to get objects: ' + response.getStatus() + ' ' + response.getBody());
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
    }

    @AuraEnabled(cacheable=false)
    public static DependencyNode getObjectDependencies(String sessionId, String instanceUrl, String objectName, Integer maxDepth, List<String> excludedObjects) {
        if (String.isBlank(sessionId) || String.isBlank(instanceUrl) || String.isBlank(objectName)) {
            throw new AuraHandledException('SessionId, instanceUrl, and objectName are required.');
        }

        System.debug('ExternalOrgQueryController.getObjectDependencies invoked for: ' + objectName);
        
        // Set defaults if not provided
        if (maxDepth == null || maxDepth <= 0) {
            maxDepth = 3;
        }
        if (excludedObjects == null) {
            excludedObjects = new List<String>();
        }
        
        Set<String> visited = new Set<String>();
        Set<String> excludedSet = new Set<String>(excludedObjects);
        return buildDependencyTree(sessionId, instanceUrl, objectName, visited, maxDepth, excludedSet, 0);
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
                        System.debug('Adding dependency for: ' + objectName + ' -> ' + relationshipName);
                        String parentObjectName = (String) referenceTo[0];
                        String fieldName = (String) field.get('name');
                        
                        DependencyNode parentNode = new DependencyNode(parentObjectName, fieldName);
                        parentNode.relationshipType = 'Lookup';
                        // Required if non-nillable and not defaulted on create
                        parentNode.isRequired = (nillable == false) && (defaultedOnCreate != true);
                        
                        // Recursively get parent dependencies with depth control
                        DependencyNode parentTree = buildDependencyTree(sessionId, instanceUrl, parentObjectName, visited, maxDepth, excludedObjects, currentDepth + 1);
                        if (parentTree != null) {
                            parentNode.parents = parentTree.parents;
                            parentNode.children = parentTree.children;
                        }
                        
                        rootNode.parents.add(parentNode);
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
        if (String.isBlank(sessionId) || String.isBlank(instanceUrl)) {
            throw new AuraHandledException('SessionId and instanceUrl are required.');
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
                    Boolean creatable = (Boolean) field.get('createable');
                    if (creatable == null || !creatable) {
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
    }

    @AuraEnabled(cacheable=false)
    public static QueryResultWrapper queryWithSession(String sessionId, String instanceUrl, String soql) {
        if (String.isBlank(sessionId) || String.isBlank(instanceUrl) || String.isBlank(soql)) {
            throw new AuraHandledException('SessionId, instanceUrl, and soql are required.');
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
            throw new AuraHandledException('Query failed: ' + response.getStatus() + ' ' + response.getBody());
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
                if (rec == null) {
                    continue;
                }
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

        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            throw new AuraHandledException('Login failed: ' + response.getStatus() + ' ' + response.getBody());
        }

        Dom.Document doc = new Dom.Document();
        doc.load(response.getBody());

        Dom.XMLNode envelope = doc.getRootElement();
        Dom.XMLNode body = envelope.getChildElement('Body', 'http://schemas.xmlsoap.org/soap/envelope/');
        if (body == null) {
            throw new AuraHandledException('Invalid SOAP response: missing Body');
        }
        Dom.XMLNode loginResponse = body.getChildElement('loginResponse', 'urn:partner.soap.sforce.com');
        if (loginResponse == null) {
            Dom.XMLNode fault = body.getChildElement('Fault', 'http://schemas.xmlsoap.org/soap/envelope/');
            if (fault != null) {
                String faultText = fault.getText();
                throw new AuraHandledException('Login fault' + (String.isBlank(faultText) ? '' : (': ' + faultText)));
            }
            throw new AuraHandledException('Invalid SOAP response: missing loginResponse');
        }
        Dom.XMLNode resultNode = loginResponse.getChildElement('result', 'urn:partner.soap.sforce.com');
        if (resultNode == null) {
            throw new AuraHandledException('Invalid SOAP response: missing result');
        }

        String sessionId = safeGetText(resultNode, 'sessionId');
        String serverUrl = safeGetText(resultNode, 'serverUrl');
        if (String.isBlank(sessionId) || String.isBlank(serverUrl)) {
            throw new AuraHandledException('Login response missing sessionId or serverUrl');
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
        s = s.replace('\'', '&apos;');
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
            throw new AuraHandledException('SOQL is required.');
        }
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
    }

    @AuraEnabled(cacheable=false)
    public static DependencyNode getObjectDependenciesCurrent(String objectName, Integer maxDepth, List<String> excludedObjects) {
        if (String.isBlank(objectName)) {
            throw new AuraHandledException('objectName is required.');
        }
        if (maxDepth == null || maxDepth < 0) maxDepth = 0;
        if (excludedObjects == null) excludedObjects = new List<String>();
        Set<String> visited = new Set<String>();
        Set<String> excluded = new Set<String>(excludedObjects);
        return buildDependencyTreeCurrent(objectName, visited, maxDepth, excluded, 0);
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
                        if (rTo != null && !rTo.isEmpty() && fd.isCreateable()) {
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
                if (fd.isCreateable()) {
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
    }

    @AuraEnabled(cacheable=false)
    public static List<InsertMapping> insertRecordsCurrent(String objectName, List<Map<String, Object>> records) {
        if (String.isBlank(objectName)) {
            throw new AuraHandledException('objectName is required');
        }
        List<InsertMapping> out = new List<InsertMapping>();
        if (records == null || records.isEmpty()) {
            return out;
        }
        Schema.SObjectType t = Schema.getGlobalDescribe().get(objectName);
        if (t == null) {
            throw new AuraHandledException('Unknown sObject: ' + objectName);
        }
        List<SObject> toInsert = new List<SObject>();
        List<String> oldIds = new List<String>();
        for (Map<String, Object> rec : records) {
            if (rec == null) continue;
            SObject sobj = t.newSObject();
            String oldId = (rec.containsKey('Id') && rec.get('Id') != null) ? String.valueOf(rec.get('Id')) : null;
            oldIds.add(oldId);
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
        for (Integer i = 0; i < results.size(); i++) {
            InsertMapping m = new InsertMapping();
            m.oldId = i < oldIds.size() ? oldIds[i] : null;
            Database.SaveResult sr = results[i];
            if (sr.isSuccess()) {
                m.success = true;
                m.newId = (String) sr.getId();
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
    }
}

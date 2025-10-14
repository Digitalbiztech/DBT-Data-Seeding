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

    public class DependencyNode {
        @AuraEnabled public String objectName;
        @AuraEnabled public String fieldName;
        @AuraEnabled public String relationshipType; // 'Lookup' or 'MasterDetail'
        @AuraEnabled public List<DependencyNode> parents;
        
        public DependencyNode() {
            this.parents = new List<DependencyNode>();
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
            HttpRequest request = new HttpRequest();
            request.setMethod('GET');
            request.setEndpoint(instanceUrl + '/services/data/v62.0/sobjects/' + objectName + '/describe/');
            request.setHeader('Authorization', 'Bearer ' + sessionId);
            request.setHeader('Content-Type', 'application/json');

            Http http = new Http();
            HTTPResponse response = http.send(request);

            if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
                System.debug('Failed to describe object ' + objectName + ': ' + response.getStatus());
                return rootNode;
            }

            Map<String, Object> untyped = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            List<Object> fields = (List<Object>) untyped.get('fields');
            
            if (fields != null) {
                for (Object fieldObj : fields) {
                    Map<String, Object> field = (Map<String, Object>) fieldObj;
                    String fieldType = (String) field.get('type');
                    String relationshipName = (String) field.get('relationshipName');
                    List<Object> referenceTo = (List<Object>) field.get('referenceTo');
                    Boolean createable = (Boolean) field.get('createable');
                    
                    // Check if this is a lookup or master-detail relationship
                    if (fieldType == 'reference' && String.isNotBlank(relationshipName) && referenceTo != null && !referenceTo.isEmpty() && createable != null && createable) {
                        System.debug('Adding dependency for: ' + objectName + ' -> ' + relationshipName);
                        String parentObjectName = (String) referenceTo[0];
                        String fieldName = (String) field.get('name');
                        
                        DependencyNode parentNode = new DependencyNode(parentObjectName, fieldName);
                        
                        // Recursively get parent dependencies with depth control
                        DependencyNode parentTree = buildDependencyTree(sessionId, instanceUrl, parentObjectName, new Set<String>(visited), maxDepth, excludedObjects, currentDepth + 1);
                        if (parentTree != null) {
                            parentNode.parents = parentTree.parents;
                        }
                        
                        rootNode.parents.add(parentNode);
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error building dependency tree for ' + objectName + ': ' + e.getMessage());
        }

        visited.remove(objectName);
        return rootNode;
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
}
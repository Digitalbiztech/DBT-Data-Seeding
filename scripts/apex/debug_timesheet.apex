String objectName = 'dbt__Timesheet__c';
Integer maxDepth = null;
ExternalOrgQueryController.DependencyNode tree = ExternalOrgQueryController.getObjectDependenciesCurrent(objectName, maxDepth, new List<String>());
System.debug('Timesheet Tree result: ' + JSON.serializePretty(tree));

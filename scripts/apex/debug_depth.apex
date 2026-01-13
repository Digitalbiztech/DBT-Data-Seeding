// Debug script to check dependency logic
String objectName = 'Opportunity'; // Try a standard object
Integer maxDepth = null; // Unlimited

System.debug('--- START DEBUG ---');
ExternalOrgQueryController.DependencyNode tree = ExternalOrgQueryController.getObjectDependenciesCurrent(objectName, maxDepth, new List<String>());
System.debug('Tree result: ' + JSON.serializePretty(tree));

// Also check specific field properties
Schema.DescribeFieldResult f = Schema.SObjectType.Opportunity.fields.AccountId;
System.debug('Opportunity.AccountId - Nillable: ' + f.isNillable() + ' DefaultedOnCreate: ' + f.isDefaultedOnCreate());

objectName = 'Case';
maxDepth = null;
ExternalOrgQueryController.DependencyNode tree2 = ExternalOrgQueryController.getObjectDependenciesCurrent(objectName, maxDepth, new List<String>());
System.debug('Case Tree result: ' + JSON.serializePretty(tree2));

System.debug('--- END DEBUG ---');

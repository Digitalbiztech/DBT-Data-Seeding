@isTest
public class DebugDurationLimit {
    @isTest
    static void testBulkInsert() {
        // Create Employee
        dbt__Employee__c emp = new dbt__Employee__c(Name = 'Test Employee', dbt__Email__c='test@example.com');
        insert emp;

        // Create Timesheet
        dbt__Timesheet__c ts = new dbt__Timesheet__c(
            dbt__Employee__c = emp.Id,
            dbt__Start_Date__c = Date.today().toStartOfWeek(),
            dbt__End_Date__c = Date.today().toStartOfWeek().addDays(6),
            dbt__Status__c = 'New'
        );
        insert ts;
        
        // Create Project
        dbt__Project__c proj = new dbt__Project__c(Name='Test Project', dbt__Billable__c='Yes', dbt__Active__c=true);
        insert proj;

        // Create Line Items
        List<dbt__Timesheet_Line_Item__c> items = new List<dbt__Timesheet_Line_Item__c>();
        
        // Item 1: 5 hours
        items.add(new dbt__Timesheet_Line_Item__c(
            dbt__Timesheet__c = ts.Id,
            dbt__Date__c = ts.dbt__Start_Date__c,
            dbt__Type__c = 'Attendance',
            dbt__Project__c = proj.Id,
            dbt__Duration__c = 5,
            dbt__Description__c = 'Item 1',
            dbt__Activity__c = 'Activity 1'
        ));

        // Item 2: 4 hours
        items.add(new dbt__Timesheet_Line_Item__c(
            dbt__Timesheet__c = ts.Id,
            dbt__Date__c = ts.dbt__Start_Date__c, // SAME DATE
            dbt__Type__c = 'Attendance',
            dbt__Project__c = proj.Id, 
            dbt__Activity__c = 'Different Activity',
            dbt__Duration__c = 4,
            dbt__Description__c = 'Item 2'
        ));
        
        System.debug('Inserting items...');
        try {
            insert items;
            System.debug('Insert successful');
        } catch (Exception e) {
            System.debug('Insert failed: ' + e.getMessage());
             if (e.getMessage().contains('Duration entered for the date has exceeded 24 hours')) {
                 System.assert(false, 'Caught Duration Limit Error: ' + e.getMessage());
             } else {
                 System.assert(false, 'Caught other error: ' + e.getMessage());
             }
        }
    }
}
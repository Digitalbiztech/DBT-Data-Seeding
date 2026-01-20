# Dependency & Import Logic

## 1. Fetching Dependencies (Child -> Parent)
When building the dependency graph, we start from the selected object (Child) and traverse upwards to find its required Parents (Lookups/Master-Detail).
- **Direction:** Child -> Parent
- **Example:** If you select `dbt__Timesheet__c` (Child), the system finds `dbt__Employee__c` (Parent) and `dbt__Project__c` (Parent).
- **Reason:** We need to know what parents are required to exist before the child can be inserted.

## 2. Importing Records (Parent -> Child)
When performing the data import, the order is reversed to satisfy Referential Integrity. Parents must exist in the destination org *before* the Child record references them.
- **Direction:** Parent -> Child
- **Example:** 
    1. Import `User` (Parent)
    2. Import `dbt__Employee__c` (Parent, depends on User)
    3. Import `dbt__Project__c` (Parent)
    4. Import `dbt__Timesheet__c` (Child, depends on Employee & Project)
- **Mechanism:** `computeExportOrder` uses a Topological Sort (Kahn's Algorithm) to determine this valid sequence.

## Summary
| Phase | Direction | Example |
| :--- | :--- | :--- |
| **Dependency Discovery** | Child &rarr; Parent | Timesheet &rarr; Employee |
| **Data Import** | Parent &rarr; Child | Employee &rarr; Timesheet |

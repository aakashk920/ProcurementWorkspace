public with sharing class VendorOnboardingController {

    public class AccountWrapper {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String industry;
        @AuraEnabled public String phone;
        @AuraEnabled public Integer totalContacts;
        @AuraEnabled public Integer openTasks;
        @AuraEnabled public String rating;
    }

    public class DashboardResponse {
        @AuraEnabled public List<AccountWrapper> records;
        @AuraEnabled public Integer totalRecords;
    }

    public class DetailResponse {
        @AuraEnabled public Account accRecord;
        @AuraEnabled public List<Contact> contacts;
        @AuraEnabled public List<Task> tasks;
    }


    /*====================================================
        LOAD ACCOUNTS
    ====================================================*/

    @AuraEnabled(cacheable=true)
    public static DashboardResponse loadAccounts(
        String searchKeyword,
        String industry,
        String rating
    ) {

        DashboardResponse response = new DashboardResponse();

        try {

            String baseQuery =
                'SELECT Id, Name, Industry, Phone, Rating, ' +
                '(SELECT Id FROM Contacts), ' +
                '(SELECT Id FROM Tasks WHERE Status != \'Completed\') ' +
                'FROM Account WHERE Id != null ';

            List<String> conditions = new List<String>();

            String searchPattern;

            if(String.isNotBlank(searchKeyword)) {
                searchPattern = '%' + searchKeyword + '%';
                conditions.add('Name LIKE :searchPattern');
            }

            if(String.isNotBlank(industry)) {
                conditions.add('Industry = :industry');
            }

            if(String.isNotBlank(rating)) {
                conditions.add('Rating = :rating');
            }

            if(!conditions.isEmpty()) {
                baseQuery += ' AND ' + String.join(conditions, ' AND ');
            }

            baseQuery += ' ORDER BY LastModifiedDate DESC LIMIT 50';

            List<Account> accList = Database.query(baseQuery);

            List<AccountWrapper> wrapperList = new List<AccountWrapper>();

            for(Account acc : accList) {

                AccountWrapper wrap = new AccountWrapper();

                wrap.accountId = acc.Id;
                wrap.accountName = acc.Name;
                wrap.industry = acc.Industry;
                wrap.phone = acc.Phone;
                wrap.rating = acc.Rating;
                wrap.totalContacts = acc.Contacts.size();
                wrap.openTasks = acc.Tasks.size();

                wrapperList.add(wrap);
            }

            response.records = wrapperList;
            response.totalRecords = wrapperList.size();

        } catch(Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }

        return response;
    }


    /*====================================================
        DETAIL PANEL
    ====================================================*/

    @AuraEnabled(cacheable=true)
    public static DetailResponse getAccountDetails(Id accountId) {

        DetailResponse response = new DetailResponse();

        try {

            response.accRecord = [
                SELECT Id,
                       Name,
                       Industry,
                       Rating,
                       Phone,
                       Website,
                       Description
                FROM Account
                WHERE Id = :accountId
                LIMIT 1
            ];

            response.contacts = [
                SELECT Id,
                       Name,
                       Email,
                       Phone,
                       Title
                FROM Contact
                WHERE AccountId = :accountId
                ORDER BY CreatedDate DESC
                LIMIT 10
            ];

            response.tasks = [
                SELECT Id,
                       Subject,
                       Status,
                       Priority,
                       ActivityDate
                FROM Task
                WHERE WhatId = :accountId
                ORDER BY CreatedDate DESC
                LIMIT 10
            ];

        } catch(Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }

        return response;
    }


    /*====================================================
        CREATE TASK
    ====================================================*/

    @AuraEnabled
    public static String createOnboardingTask(
        Id accountId,
        String subject
    ) {

        Savepoint sp = Database.setSavepoint();

        try {

            Task t = new Task();
            t.WhatId = accountId;
            t.Subject = subject;
            t.Status = 'Not Started';
            t.Priority = 'High';
            t.ActivityDate = System.today() + 2;

            insert t;

            return 'Task Created Successfully';

        } catch(Exception ex) {

            Database.rollback(sp);
            throw new AuraHandledException(ex.getMessage());
        }
    }
}
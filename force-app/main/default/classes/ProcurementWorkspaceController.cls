public with sharing class ProcurementWorkspaceController {

    public class ProcurementException extends Exception {}
    private static final Integer MAX_PAGE_SIZE  = 50;
    private static final Integer DEFAULT_PAGE   = 1;
    private static final String  TASK_PRIORITY  = 'High';
    private static final String  TASK_STATUS    = 'Not Started';

    public class WorkspaceResponse {
        @AuraEnabled public List<OpportunityWrapper> records;
        @AuraEnabled public Integer                  totalRecords;
        @AuraEnabled public Integer                  totalPages;
        @AuraEnabled public Integer                  currentPage;
        @AuraEnabled public SummaryStats             stats;
        @AuraEnabled public String                   message;
    }

    public class OpportunityWrapper {
        @AuraEnabled public Id      oppId;
        @AuraEnabled public String  oppName;
        @AuraEnabled public String  accountName;
        @AuraEnabled public String  stageName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String  ownerName;
        @AuraEnabled public Date    closeDate;
        @AuraEnabled public Decimal probability;
        @AuraEnabled public String  description;
        @AuraEnabled public Boolean isOverdue;    
        @AuraEnabled public String  healthLabel;
    }

    public class SummaryStats {
        @AuraEnabled public Integer totalOpps;
        @AuraEnabled public Decimal totalPipeline;
        @AuraEnabled public Decimal avgDealSize;
        @AuraEnabled public Integer overdueCount;
    }

    public class DetailWrapper {
        @AuraEnabled public Opportunity     opportunityRecord;
        @AuraEnabled public List<Contact>   contacts;
        @AuraEnabled public List<Task>      activities;
        @AuraEnabled public List<NoteItem>  notes;
        @AuraEnabled public StageHistory    stageProgress;
    }

    public class NoteItem {
        @AuraEnabled public Id     noteId;
        @AuraEnabled public String title;
        @AuraEnabled public String body;
        @AuraEnabled public String createdByName;
        @AuraEnabled public String createdDate;
    }

    public class StageHistory {
        @AuraEnabled public String        currentStage;
        @AuraEnabled public List<String>  allStages;
        @AuraEnabled public Integer       currentIndex;
    }
    public class CreateTaskResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  message;
        @AuraEnabled public Id      taskId;
    }
    public class BulkUpdateRequest {
        @AuraEnabled public Id     oppId;
        @AuraEnabled public String newStage;
        @AuraEnabled public String note;
    }

    public class BulkUpdateResponse {
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer failureCount;
        @AuraEnabled public List<String> errors;
    }

    @AuraEnabled
    public static WorkspaceResponse getWorkspaceData(
        String        searchKeyword,
        List<String>  stages,
        Decimal       minAmount,
        Decimal       maxAmount,
        Integer       pageSize,
        Integer       pageNumber,
        String        sortField,
        String        sortDirection
    ) {
        WorkspaceResponse response = new WorkspaceResponse();

        try {
            validateObjectAccess('Opportunity');
            pageSize   = (pageSize   == null || pageSize   <= 0) ? 10 : Math.min(pageSize, MAX_PAGE_SIZE);
            pageNumber = (pageNumber == null || pageNumber <= 0) ? DEFAULT_PAGE : pageNumber;
            List<String> conditions = new List<String>();
            String searchPattern;

            if (String.isNotBlank(searchKeyword)) {
                searchPattern = '%' + String.escapeSingleQuotes(searchKeyword) + '%';
                conditions.add('Name LIKE :searchPattern');
            }

            if (stages != null && !stages.isEmpty()) {
                conditions.add('StageName IN :stages');
            }

            if (minAmount != null) {
                conditions.add('Amount >= :minAmount');
            }

            if (maxAmount != null) {
                conditions.add('Amount <= :maxAmount');
            }

            String whereClause = conditions.isEmpty()
                ? ''
                : ' AND ' + String.join(conditions, ' AND ');

            Set<String> allowedSortFields = new Set<String>{
                'Name', 'Amount', 'CloseDate', 'StageName', 'LastModifiedDate'
            };
            String safeSortField = allowedSortFields.contains(sortField)
                ? sortField
                : 'LastModifiedDate';

            String safeSortDir = (sortDirection == 'ASC') ? 'ASC' : 'DESC';

            String countQuery =
                'SELECT COUNT() FROM Opportunity WHERE IsDeleted = false' + whereClause;
            Integer totalRecords = Database.countQuery(countQuery);
            Integer offsetValue = (pageNumber - 1) * pageSize;

            String mainQuery =
                'SELECT Id, Name, StageName, Amount, CloseDate, ' +
                '       Probability, Description, Owner.Name, Account.Name ' +
                'FROM   Opportunity ' +
                'WHERE  IsDeleted = false' + whereClause +
                ' ORDER BY ' + safeSortField + ' ' + safeSortDir +
                ' LIMIT :pageSize OFFSET :offsetValue';

            List<Opportunity> oppList = Database.query(mainQuery);
            String aggQuery =
                            'SELECT COUNT(Id) totalOpps, ' +
                            '       SUM(Amount) totalPipeline, ' +
                            '       AVG(Amount) avgDealSize ' +
                            'FROM Opportunity ' +
                            'WHERE IsDeleted = false AND StageName != \'Closed Lost\'' + whereClause;

            AggregateResult aggResult = (AggregateResult) Database.query(aggQuery);
            Date today = Date.today();
            String overdueQuery =
                'SELECT COUNT() FROM Opportunity ' +
                'WHERE  IsDeleted = false ' +
                'AND    CloseDate < :today ' +
                'AND    IsClosed  = false' + whereClause;
            Integer overdueCount = Database.countQuery(overdueQuery);

            List<OpportunityWrapper> wrapperList = new List<OpportunityWrapper>();

            for (Opportunity opp : oppList) {
                OpportunityWrapper wrap = new OpportunityWrapper();

                wrap.oppId       = opp.Id;
                wrap.oppName     = opp.Name;
                wrap.accountName = opp.Account != null ? opp.Account.Name : '—';
                wrap.stageName   = opp.StageName;
                wrap.amount      = opp.Amount;
                wrap.ownerName   = opp.Owner.Name;
                wrap.closeDate   = opp.CloseDate;
                wrap.probability = opp.Probability;
                wrap.description = opp.Description;

                wrap.isOverdue = (opp.CloseDate != null
                                  && opp.CloseDate < Date.today()
                                  && opp.StageName != 'Closed Won'
                                  && opp.StageName != 'Closed Lost');

                if      (opp.Probability >= 70) { wrap.healthLabel = 'Hot';  }
                else if (opp.Probability >= 40) { wrap.healthLabel = 'Warm'; }
                else                            { wrap.healthLabel = 'Cold'; }

                wrapperList.add(wrap);
            }
            SummaryStats stats    = new SummaryStats();
            stats.totalOpps       = (Integer) aggResult.get('totalOpps');
            stats.totalPipeline   = (Decimal) aggResult.get('totalPipeline');
            stats.avgDealSize     = (Decimal) aggResult.get('avgDealSize');
            stats.overdueCount    = overdueCount;
            response.records      = wrapperList;
            response.totalRecords = totalRecords;
            response.totalPages   = (Integer) Math.ceil((Double) totalRecords / pageSize);
            response.currentPage  = pageNumber;
            response.stats        = stats;
            response.message      = 'Success';

        } catch (Exception ex) {
            throw new AuraHandledException(
                'Error loading workspace data: ' + ex.getMessage()
            );
        }

        return response;
    }
    @AuraEnabled(cacheable=true)
    public static DetailWrapper getOpportunityDetails(Id opportunityId) {

        DetailWrapper detailWrap = new DetailWrapper();

        try {
            Opportunity opp = [
                SELECT Id,
                       Name,
                       StageName,
                       Amount,
                       Description,
                       Probability,
                       CloseDate,
                       AccountId,
                       Account.Name,
                       Account.Phone,
                       Account.Industry,
                       Owner.Name
                FROM   Opportunity
                WHERE  Id = :opportunityId
                LIMIT  1
            ];

            List<Contact> contactList = [
                SELECT Id, Name, Email, Phone, Title
                FROM   Contact
                WHERE  AccountId = :opp.AccountId
                ORDER  BY CreatedDate DESC
                LIMIT  10
            ];

            List<Task> taskList = [
                SELECT Id, Subject, Status, Priority, ActivityDate, Description
                FROM   Task
                WHERE  WhatId = :opportunityId
                ORDER  BY CreatedDate DESC
                LIMIT  10
            ];
            List<ContentDocumentLink> cdLinks = [
                SELECT ContentDocument.Id,
                       ContentDocument.Title,
                       ContentDocument.LatestPublishedVersion.TextPreview,
                       ContentDocument.CreatedBy.Name,
                       ContentDocument.CreatedDate
                FROM   ContentDocumentLink
                WHERE  LinkedEntityId = :opportunityId
                AND    ContentDocument.FileType = 'SNOTE'
                ORDER  BY ContentDocument.CreatedDate DESC
                LIMIT  5
            ];

            List<NoteItem> noteItems = new List<NoteItem>();
            for (ContentDocumentLink cdl : cdLinks) {
                NoteItem n    = new NoteItem();
                n.noteId      = cdl.ContentDocument.Id;
                n.title       = cdl.ContentDocument.Title;
                n.body        = cdl.ContentDocument.LatestPublishedVersion != null
                                ? cdl.ContentDocument.LatestPublishedVersion.TextPreview
                                : '';
                n.createdByName = cdl.ContentDocument.CreatedBy.Name;
                n.createdDate   = String.valueOf(
                    cdl.ContentDocument.CreatedDate.format()
                );
                noteItems.add(n);
            }
            List<String> orderedStages = new List<String>{
                'Prospecting',
                'Qualification',
                'Needs Analysis',
                'Value Proposition',
                'Id. Decision Makers',
                'Perception Analysis',
                'Proposal/Price Quote',
                'Negotiation/Review',
                'Closed Won'
            };

            Integer currentIdx = orderedStages.indexOf(opp.StageName);
            if (currentIdx == -1) { currentIdx = 0; }

            StageHistory sp       = new StageHistory();
            sp.currentStage       = opp.StageName;
            sp.allStages          = orderedStages;
            sp.currentIndex       = currentIdx;
            detailWrap.opportunityRecord = opp;
            detailWrap.contacts          = contactList;
            detailWrap.activities        = taskList;
            detailWrap.notes             = noteItems;
            detailWrap.stageProgress     = sp;

        } catch (Exception ex) {
            throw new AuraHandledException(
                'Error loading opportunity details: ' + ex.getMessage()
            );
        }

        return detailWrap;
    }
    @AuraEnabled
    public static CreateTaskResponse createFollowUpTask(
        Id     opportunityId,
        String subject,
        Date   dueDate
    ) {
        CreateTaskResponse response = new CreateTaskResponse();
        Savepoint sp = Database.setSavepoint();

        try {
            Opportunity opp = [
                SELECT Id, Name, OwnerId
                FROM   Opportunity
                WHERE  Id = :opportunityId
                LIMIT  1
            ];

            Task t          = new Task();
            t.Subject       = String.isNotBlank(subject) ? subject : 'Procurement Follow-up';
            t.WhatId        = opp.Id;
            t.OwnerId       = opp.OwnerId;
            t.Priority      = TASK_PRIORITY;
            t.Status        = TASK_STATUS;
            t.ActivityDate  = (dueDate != null) ? dueDate : Date.today().addDays(3);
            t.Description   = 'Auto-created by Procurement Workspace on ' + System.now();

            insert t;
            opp.Description = 'Last Follow-up: ' + t.Subject +
                              ' | Created: ' + System.now().format();
            update opp;

            response.success = true;
            response.message = 'Task "' + t.Subject + '" created successfully.';
            response.taskId  = t.Id;

        } catch (Exception ex) {
            Database.rollback(sp);
            response.success = false;
            response.message = ex.getMessage();
            throw new AuraHandledException(
                'Task creation failed: ' + ex.getMessage()
            );
        }

        return response;
    }

    @AuraEnabled
    public static BulkUpdateResponse bulkUpdateStage(
        List<BulkUpdateRequest> updateRequests
    ) {
        BulkUpdateResponse resp = new BulkUpdateResponse();
        resp.errors             = new List<String>();

        Set<String> validStages = new Set<String>{
            'Prospecting', 'Qualification', 'Needs Analysis',
            'Value Proposition', 'Id. Decision Makers',
            'Perception Analysis', 'Proposal/Price Quote',
            'Negotiation/Review', 'Closed Won', 'Closed Lost'
        };

        List<Opportunity> toUpdate = new List<Opportunity>();

        for (BulkUpdateRequest req : updateRequests) {
            if (!validStages.contains(req.newStage)) {
                resp.errors.add('Invalid stage "' + req.newStage +
                                '" for Opp Id: ' + req.oppId);
                continue;
            }

            Opportunity o = new Opportunity(Id = req.oppId);
            o.StageName   = req.newStage;

            if (String.isNotBlank(req.note)) {
                o.Description = req.note;
            }

            toUpdate.add(o);
        }

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> results =
                Database.update(toUpdate, false); 

            resp.successCount = 0;
            resp.failureCount = 0;

            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    resp.successCount++;
                } else {
                    resp.failureCount++;
                    for (Database.Error err : results[i].getErrors()) {
                        resp.errors.add(
                            'Opp ' + toUpdate[i].Id +
                            ': ' + err.getMessage()
                        );
                    }
                }
            }
        }

        return resp;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getStagePicklistValues() {

        List<Map<String, String>> options = new List<Map<String, String>>();

        Schema.DescribeFieldResult fieldResult =
            Opportunity.StageName.getDescribe();

        for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {
            if (entry.isActive()) {
                Map<String, String> opt = new Map<String, String>{
                    'label' => entry.getLabel(),
                    'value' => entry.getValue()
                };
                options.add(opt);
            }
        }

        return options;
    }

    private static void validateObjectAccess(String objectApiName) {

        Schema.SObjectType objType =
            Schema.getGlobalDescribe().get(objectApiName);

        if (objType == null) {
            throw new ProcurementException(
                'Object not found in schema: ' + objectApiName
            );
        }

        if (!objType.getDescribe().isAccessible()) {
            throw new AuraHandledException(
                'Insufficient access to ' + objectApiName + ' object.'
            );
        }
    }

    private static void checkFieldAccess(
        Schema.SObjectField field,
        String              context
    ) {
        if (!field.getDescribe().isAccessible()) {
            throw new AuraHandledException(
                'Field access denied in context: ' + context
            );
        }
    }
}
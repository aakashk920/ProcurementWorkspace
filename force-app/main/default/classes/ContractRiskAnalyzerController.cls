public with sharing class ContractRiskAnalyzerController {

    /*====================================================
        WRAPPER CLASSES
    ====================================================*/

    public class RiskWrapper {

        @AuraEnabled public Id oppId;
        @AuraEnabled public String oppName;
        @AuraEnabled public String accountName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String stageName;
        @AuraEnabled public Integer riskScore;
        @AuraEnabled public String riskLevel;
        @AuraEnabled public String recommendedAction;
        @AuraEnabled public String slaHealth;
        @AuraEnabled public Integer daysToClose;
        @AuraEnabled public Boolean hasOpenTasks;
    }


    public class DashboardResponse {

        @AuraEnabled public List<RiskWrapper> records;

        @AuraEnabled public Integer totalDeals;
        @AuraEnabled public Integer highRiskDeals;
        @AuraEnabled public Decimal totalRevenue;
        @AuraEnabled public Integer pendingFollowUps;
    }


    /*====================================================
        LOAD DASHBOARD DATA
    ====================================================*/

    @AuraEnabled(cacheable=true)
    public static DashboardResponse loadRiskDashboard() {

        DashboardResponse response = new DashboardResponse();

        try {

            List<Opportunity> oppList = [
                SELECT Id,
                       Name,
                       StageName,
                       Amount,
                       Probability,
                       CloseDate,
                       LastActivityDate,
                       Account.Name,
                       (
                           SELECT Id,
                                  Status
                           FROM Tasks
                           WHERE Status != 'Completed'
                       )
                FROM Opportunity
                WHERE IsClosed = false
                ORDER BY Amount DESC
                LIMIT 50
            ];

            List<RiskWrapper> wrapperList = new List<RiskWrapper>();

            Integer highRiskCount = 0;
            Decimal totalAmount = 0;
            Integer pendingTaskCount = 0;

            for(Opportunity opp : oppList) {

                RiskWrapper wrap = new RiskWrapper();

                wrap.oppId = opp.Id;
                wrap.oppName = opp.Name;
                wrap.accountName = opp.Account != null
                    ? opp.Account.Name
                    : '';

                wrap.amount = opp.Amount;
                wrap.stageName = opp.StageName;

                Integer riskScore = 0;

                /*====================================
                    RISK ENGINE
                ====================================*/

                if(opp.Probability < 40) {
                    riskScore += 30;
                }

                if(opp.Amount != null && opp.Amount > 100000) {
                    riskScore += 20;
                }

                if(opp.CloseDate != null) {

                    Integer daysLeft =
                        Date.today().daysBetween(opp.CloseDate);

                    wrap.daysToClose = daysLeft;

                    if(daysLeft < 7) {
                        riskScore += 25;
                    }
                }

                if(opp.Tasks.isEmpty()) {
                    riskScore += 25;
                }

                wrap.riskScore = riskScore;

                /*====================================
                    RISK LEVEL
                ====================================*/

                if(riskScore >= 70) {
                    wrap.riskLevel = 'High';
                    highRiskCount++;
                }
                else if(riskScore >= 40) {
                    wrap.riskLevel = 'Medium';
                }
                else {
                    wrap.riskLevel = 'Low';
                }

                /*====================================
                    SLA HEALTH
                ====================================*/

                if(riskScore >= 70) {
                    wrap.slaHealth = 'Critical';
                }
                else if(riskScore >= 40) {
                    wrap.slaHealth = 'Warning';
                }
                else {
                    wrap.slaHealth = 'Healthy';
                }

                /*====================================
                    SMART RECOMMENDATION
                ====================================*/

                if(riskScore >= 70) {
                    wrap.recommendedAction =
                        'Immediate Manager Follow-up';
                }
                else if(riskScore >= 40) {
                    wrap.recommendedAction =
                        'Schedule Customer Meeting';
                }
                else {
                    wrap.recommendedAction =
                        'Monitor Progress';
                }

                wrap.hasOpenTasks = !opp.Tasks.isEmpty();

                if(!opp.Tasks.isEmpty()) {
                    pendingTaskCount++;
                }

                totalAmount += opp.Amount != null
                    ? opp.Amount
                    : 0;

                wrapperList.add(wrap);
            }

            response.records = wrapperList;
            response.totalDeals = wrapperList.size();
            response.highRiskDeals = highRiskCount;
            response.totalRevenue = totalAmount;
            response.pendingFollowUps = pendingTaskCount;

        } catch(Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }

        return response;
    }


    /*====================================================
        BULK CREATE TASKS
    ====================================================*/

    @AuraEnabled
    public static String createBulkFollowUps(List<Id> opportunityIds) {

        Savepoint sp = Database.setSavepoint();

        try {

            List<Task> taskList = new List<Task>();

            for(Id oppId : opportunityIds) {

                Task t = new Task();
                t.WhatId = oppId;
                t.Subject = 'Urgent Risk Follow-up';
                t.Status = 'Not Started';
                t.Priority = 'High';
                t.ActivityDate = System.today() + 1;

                taskList.add(t);
            }

            if(!taskList.isEmpty()) {
                insert taskList;
            }

            return 'Bulk Follow-up Tasks Created Successfully';

        } catch(Exception ex) {

            Database.rollback(sp);
            throw new AuraHandledException(ex.getMessage());
        }
    }
}
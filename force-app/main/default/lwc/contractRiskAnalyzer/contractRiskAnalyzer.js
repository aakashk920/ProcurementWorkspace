import { LightningElement, track } from 'lwc';
import loadRiskDashboard from '@salesforce/apex/ContractRiskAnalyzerController.loadRiskDashboard';
import createBulkFollowUps from '@salesforce/apex/ContractRiskAnalyzerController.createBulkFollowUps';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class ContractRiskAnalyzer extends LightningElement {

    @track records = [];

    totalDeals = 0;
    highRiskDeals = 0;
    totalRevenue = 0;
    pendingFollowUps = 0;

    selectedRecords = [];


    connectedCallback() {
        this.loadDashboard();
    }


    async loadDashboard() {

        try {

            const response = await loadRiskDashboard();

            this.records = response.records;
            this.totalDeals = response.totalDeals;
            this.highRiskDeals = response.highRiskDeals;
            this.totalRevenue = response.totalRevenue;
            this.pendingFollowUps = response.pendingFollowUps;

        } catch(error) {
            this.showToast(
                'Error',
                error.body.message,
                'error'
            );
        }
    }


    handleSelection(event) {

        const recordId = event.target.dataset.id;

        if(event.target.checked) {

            if(!this.selectedRecords.includes(recordId)) {
                this.selectedRecords.push(recordId);
            }
        }
        else {

            this.selectedRecords = this.selectedRecords.filter(
                item => item !== recordId
            );
        }
    }


    async handleBulkTaskCreation() {

        if(this.selectedRecords.length === 0) {

            this.showToast(
                'Error',
                'Please select at least one opportunity',
                'error'
            );

            return;
        }

        try {

            const response = await createBulkFollowUps({
                opportunityIds: this.selectedRecords
            });

            this.showToast(
                'Success',
                response,
                'success'
            );

            this.selectedRecords = [];

            await this.loadDashboard();

        } catch(error) {

            this.showToast(
                'Error',
                error.body.message,
                'error'
            );
        }
    }


    showToast(title, message, variant) {

        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}
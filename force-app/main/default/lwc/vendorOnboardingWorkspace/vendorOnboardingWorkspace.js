import { LightningElement, track } from 'lwc';
import loadAccounts from '@salesforce/apex/VendorOnboardingController.loadAccounts';
import getAccountDetails from '@salesforce/apex/VendorOnboardingController.getAccountDetails';
import createOnboardingTask from '@salesforce/apex/VendorOnboardingController.createOnboardingTask';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class VendorOnboardingWorkspace extends LightningElement {

    @track records = [];
    @track detailRecord;
    selectedRecordId;
    searchKeyword = '';
    industry = '';
    rating = '';
    delayTimeout;

    industryOptions = [
        { label: 'Banking', value: 'Banking' },
        { label: 'Technology', value: 'Technology' },
        { label: 'Healthcare', value: 'Healthcare' }
    ];

    ratingOptions = [
        { label: 'Hot', value: 'Hot' },
        { label: 'Warm', value: 'Warm' },
        { label: 'Cold', value: 'Cold' }
    ];

    connectedCallback() {
        this.loadAccounts();
    }

    async loadAccounts() {
        try {
            const response = await loadAccounts({
                searchKeyword: this.searchKeyword,
                industry: this.industry,
                rating: this.rating
            });
            this.records = response.records;

        } catch(error) {
            this.showToast('Error', error.body.message, 'error');
        }
    }

    handleSearch(event) {
        window.clearTimeout(this.delayTimeout);
        const value = event.target.value;
        this.delayTimeout = setTimeout(() => {
            this.searchKeyword = value;
            this.loadAccounts();
        }, 500);
    }

    handleIndustry(event) {
        this.industry = event.detail.value;
    }

    handleRating(event) {
        this.rating = event.detail.value;
    }

    async handleTileClick(event) {
        try {
            this.selectedRecordId = event.currentTarget.dataset.id;
            this.detailRecord = await getAccountDetails({
                accountId: this.selectedRecordId
            });
        } catch(error) {
            this.showToast('Error', error.body.message, 'error');
        }
    }

    async handleCreateTask() {
        try {
            const response = await createOnboardingTask({
                accountId: this.selectedRecordId,
                subject: 'Customer Onboarding Follow-up'
            });
            this.showToast('Success', response, 'success');
        } catch(error) {
            this.showToast('Error', error.body.message, 'error');
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
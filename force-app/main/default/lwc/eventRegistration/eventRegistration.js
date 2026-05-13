import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent }               from 'lightning/platformShowToastEvent';
import getActiveCampaigns  from '@salesforce/apex/EventRegistrationController.getActiveCampaigns';
import registerAttendee    from '@salesforce/apex/EventRegistrationController.registerAttendee';
import processCheckIn      from '@salesforce/apex/EventRegistrationController.processCheckIn';
import getCampaignMembers  from '@salesforce/apex/EventRegistrationController.getCampaignMembers';
import getCampaignStats    from '@salesforce/apex/EventRegistrationController.getCampaignStats';

const COLUMNS = [
    {
        label      : 'First Name',
        fieldName  : 'contactFirstName',
        type       : 'text',
        sortable   : true
    },
    {
        label      : 'Last Name',
        fieldName  : 'contactLastName',
        type       : 'text',
        sortable   : true
    },
    {
        label      : 'Email',
        fieldName  : 'contactEmail',
        type       : 'email',
        sortable   : true
    },
    {
        label      : 'Phone',
        fieldName  : 'contactPhone',
        type       : 'phone'
    },
    {
        label      : 'Status',
        fieldName  : 'Status',
        type       : 'text',
        sortable   : true
    },
    {
        label      : 'Checked In',
        fieldName  : 'Is_Checked_In__c',
        type       : 'boolean',
        sortable   : true,
        cellAttributes: { alignment: 'center' }
    },
    {
        label      : 'Check-In Time',
        fieldName  : 'Check_In_DateTime__c',
        type       : 'date',
        typeAttributes: {
            year    : 'numeric',
            month   : 'short',
            day     : '2-digit',
            hour    : '2-digit',
            minute  : '2-digit'
        },
        sortable   : true
    }
];

export default class EventRegistration extends LightningElement {

    @track activeTab = 'register';

    @track notification = {
        message     : '',
        cssClass    : '',
        icon        : '',
        iconVariant : ''
    };

    @track allCampaigns = [];
    @track isLoadingCampaigns = false;
    @track selectedCampaignId = '';
    @track selectedCampaign = null;
    @track formData = {
        firstName : '',
        lastName  : '',
        email     : '',
        phone     : '',
        title     : ''
    };
    @track isRegistering = false;
    @track showQrCode = false;
    @track qrCodeUrl = '';
    @track registrationId = '';
    @track qrInputValue = '';
    @track isCheckingIn = false;
    @track checkInResult = null;
    @track dashboardCampaignId = '';
    @track campaignMembers = [];
    @track isLoadingAttendees = false;

    @track stats = {
        totalRegistered : 0,
        totalCheckedIn  : 0,
        pendingCheckIn  : 0
    };

    @track sortedBy        = 'contactLastName';
    @track sortedDirection = 'asc';
    columns = COLUMNS;
    connectedCallback() {
        this.loadCampaigns();
    }
    loadCampaigns() {
        this.isLoadingCampaigns = true;

        getActiveCampaigns()
            .then(data => {
                this.allCampaigns       = data;
                this.isLoadingCampaigns = false;
            })
            .catch(error => {
                this.isLoadingCampaigns = false;
                this.showNotification(
                    'error',
                    'Could not load campaigns: ' + this.extractError(error)
                );
            });
    }

    loadAttendeesAndStats(campaignId) {
        if (!campaignId) return;

        this.isLoadingAttendees = true;
        this.campaignMembers    = [];

        Promise.all([
            getCampaignMembers({ campaignId }),
            getCampaignStats({ campaignId })
        ])
        .then(([members, statsData]) => {

            this.campaignMembers = members.map(cm => ({
                ...cm,
                contactFirstName : cm.Contact ? cm.Contact.FirstName  : '',
                contactLastName  : cm.Contact ? cm.Contact.LastName   : '',
                contactEmail     : cm.Contact ? cm.Contact.Email      : '',
                contactPhone     : cm.Contact ? cm.Contact.Phone      : ''
            }));

            this.campaignMembers = this.sortData(
                this.campaignMembers,
                this.sortedBy,
                this.sortedDirection
            );

            this.stats = {
                totalRegistered : statsData.totalRegistered || 0,
                totalCheckedIn  : statsData.totalCheckedIn  || 0,
                pendingCheckIn  : statsData.pendingCheckIn  || 0
            };

            this.isLoadingAttendees = false;
        })
        .catch(error => {
            this.isLoadingAttendees = false;
            this.showNotification(
                'error',
                'Error loading attendees: ' + this.extractError(error)
            );
        });
    }

    handleTabChange(event) {
        this.activeTab = event.target.value;
        if (this.activeTab === 'attendees' && this.dashboardCampaignId) {
            this.loadAttendeesAndStats(this.dashboardCampaignId);
        }
    }

    handleCampaignChange(event) {
        this.selectedCampaignId = event.detail.value;
        this.selectedCampaign   = this.allCampaigns.find(
            c => c.id === this.selectedCampaignId
        ) || null;

        this.showQrCode = false;
        this.qrCodeUrl  = '';
    }

    handleFormChange(event) {
        const fieldName = event.target.name;
        this.formData   = {
            ...this.formData,
            [fieldName] : event.detail.value
        };
    }

    handleRegister() {
        if (!this.selectedCampaignId) {
            this.showNotification('warning', 'Please select a Campaign / Event first.');
            return;
        }

        const allInputs = this.template.querySelectorAll('lightning-input');
        let isValid     = true;

        allInputs.forEach(input => {
            if (!input.reportValidity()) {
                isValid = false;
            }
        });

        if (!isValid) {
            this.showNotification('warning', 'Please fill in all required fields correctly.');
            return;
        }
        const input = {
            firstName  : this.formData.firstName,
            lastName   : this.formData.lastName,
            email      : this.formData.email,
            phone      : this.formData.phone,
            title      : this.formData.title,
            campaignId : this.selectedCampaignId
        };

        this.isRegistering = true;
        this.showQrCode    = false;

        registerAttendee({ input })
            .then(result => {
                this.isRegistering = false;

                if (result.success) {
                    this.qrCodeUrl      = result.qrCodeUrl;
                    this.registrationId = result.campaignMemberId;
                    this.showQrCode     = true;

                    this.showNotification('success', result.message);
                    this.dispatchEvent(
                        new CustomEvent('registrationsuccess', {
                            detail : {
                                campaignMemberId : result.campaignMemberId,
                                contactId        : result.contactId
                            }
                        })
                    );
                } else {
                    this.showNotification('warning', result.message);
                }
            })
            .catch(error => {
                this.isRegistering = false;
                this.showNotification(
                    'error',
                    'Registration failed: ' + this.extractError(error)
                );
            });
    }

    handleReset() {
        this.formData = {
            firstName : '',
            lastName  : '',
            email     : '',
            phone     : '',
            title     : ''
        };
        this.showQrCode           = false;
        this.qrCodeUrl            = '';
        this.registrationId       = '';
        this.selectedCampaignId   = '';
        this.selectedCampaign     = null;
        this.clearNotification();
    }

    handleQrInputChange(event) {
        this.qrInputValue = event.detail.value;
    }

    handleQrKeyDown(event) {
        if (event.key === 'Enter' && this.qrInputValue.trim()) {
            this.handleCheckIn();
        }
    }

    handleCheckIn() {
        if (!this.qrInputValue.trim()) {
            this.showNotification('warning', 'Please enter or scan a QR code first.');
            return;
        }

        this.isCheckingIn  = true;
        this.checkInResult = null;

        processCheckIn({ qrData : this.qrInputValue.trim() })
            .then(result => {
                this.isCheckingIn = false;

                if (result.success && !result.alreadyCheckedIn) {
                  
                    this.checkInResult = {
                        ...result,
                        icon        : 'action:approval',
                        iconVariant : 'success',
                        cssClass    : 'checkin-success'
                    };
                    this.showNotification('success', result.message);

                } else if (result.success && result.alreadyCheckedIn) {
                 
                    this.checkInResult = {
                        ...result,
                        icon        : 'utility:warning',
                        iconVariant : 'warning',
                        cssClass    : 'checkin-warning'
                    };
                    this.showNotification('warning', result.message);

                } else {
                    
                    this.checkInResult = null;
                    this.showNotification('error', result.message);
                }
            })
            .catch(error => {
                this.isCheckingIn  = false;
                this.checkInResult = null;
                this.showNotification(
                    'error',
                    'Check-in failed: ' + this.extractError(error)
                );
            });
    }

    handleClearCheckIn() {
        this.qrInputValue  = '';
        this.checkInResult = null;
        this.clearNotification();
    }

    handleDashboardCampaignChange(event) {
        this.dashboardCampaignId = event.detail.value;
        this.loadAttendeesAndStats(this.dashboardCampaignId);
    }

    handleRefreshAttendees() {
        if (this.dashboardCampaignId) {
            this.loadAttendeesAndStats(this.dashboardCampaignId);
        }
    }

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.sortedBy        = fieldName;
        this.sortedDirection = sortDirection;
        this.campaignMembers = this.sortData(
            [...this.campaignMembers],
            fieldName,
            sortDirection
        );
    }

    showNotification(type, message) {
        const configMap = {
            success : {
                cssClass    : 'notification-banner notification-banner_success slds-notify slds-notify_alert slds-theme_success slds-p-around_small slds-m-around_medium',
                icon        : 'utility:check',
                iconVariant : 'inverse'
            },
            warning : {
                cssClass    : 'notification-banner notification-banner_warning slds-notify slds-notify_alert slds-theme_warning slds-p-around_small slds-m-around_medium',
                icon        : 'utility:warning',
                iconVariant : 'inverse'
            },
            error   : {
                cssClass    : 'notification-banner notification-banner_error slds-notify slds-notify_alert slds-theme_error slds-p-around_small slds-m-around_medium',
                icon        : 'utility:error',
                iconVariant : 'inverse'
            },
            info    : {
                cssClass    : 'notification-banner notification-banner_info slds-notify slds-notify_alert slds-theme_info slds-p-around_small slds-m-around_medium',
                icon        : 'utility:info',
                iconVariant : 'inverse'
            }
        };

        const config = configMap[type] || configMap.info;

        this.notification = {
            message     : message,
            cssClass    : config.cssClass,
            icon        : config.icon,
            iconVariant : config.iconVariant
        };

        this.dispatchEvent(
            new ShowToastEvent({
                title   : type.charAt(0).toUpperCase() + type.slice(1),
                message : message,
                variant : type === 'warning' ? 'warning' : type
            })
        );
    }

    clearNotification() {
        this.notification = {
            message     : '',
            cssClass    : '',
            icon        : '',
            iconVariant : ''
        };
    }


    get campaignOptions() {
        return this.allCampaigns.map(c => ({
            label : c.name + (c.startDate ? ' (' + c.startDate + ')' : ''),
            value : c.id
        }));
    }

    get formattedStartDate() {
        if (!this.selectedCampaign || !this.selectedCampaign.startDate) {
            return 'Not set';
        }
        return new Date(this.selectedCampaign.startDate).toLocaleDateString(
            'en-IN', { year: 'numeric', month: 'long', day: 'numeric' }
        );
    }

    get formattedEndDate() {
        if (!this.selectedCampaign || !this.selectedCampaign.endDate) {
            return 'Not set';
        }
        return new Date(this.selectedCampaign.endDate).toLocaleDateString(
            'en-IN', { year: 'numeric', month: 'long', day: 'numeric' }
        );
    }

    get checkInResultCssClass() {
        if (!this.checkInResult) return '';
        return this.checkInResult.alreadyCheckedIn
            ? 'checkin-result slds-box slds-p-around_medium slds-theme_warning slds-m-top_medium'
            : 'checkin-result slds-box slds-p-around_medium slds-theme_success slds-m-top_medium';
    }

    extractError(error) {
        if (!error) return 'Unknown error occurred.';
        if (error.body && error.body.message) return error.body.message;
        if (error.message)                    return error.message;
        return JSON.stringify(error);
    }

    sortData(data, fieldName, direction) {
        const multiplier = direction === 'asc' ? 1 : -1;

        return [...data].sort((a, b) => {
            const valA = a[fieldName] != null ? a[fieldName] : '';
            const valB = b[fieldName] != null ? b[fieldName] : '';

            if (valA === valB) return 0;
            if (typeof valA === 'string') {
                return valA.localeCompare(valB) * multiplier;
            }
            return (valA > valB ? 1 : -1) * multiplier;
        });
    }
}
import { LightningElement, track, wire } from 'lwc';
import getWorkspaceData      from '@salesforce/apex/ProcurementWorkspaceController.getWorkspaceData';
import getOpportunityDetails from '@salesforce/apex/ProcurementWorkspaceController.getOpportunityDetails';
import createFollowUpTask    from '@salesforce/apex/ProcurementWorkspaceController.createFollowUpTask';
import bulkUpdateStage       from '@salesforce/apex/ProcurementWorkspaceController.bulkUpdateStage';
import getStagePicklistValues from '@salesforce/apex/ProcurementWorkspaceController.getStagePicklistValues';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';
const DEBOUNCE_DELAY = 400;
const PAGE_SIZE      = 10;

const CURRENCY_FORMATTER = new Intl.NumberFormat('en-US', {
    style    : 'currency',
    currency : 'USD',
    maximumFractionDigits: 0
});

export default class ProcurementWorkspace extends LightningElement {

    @track records       = [];    
    @track detailRecord;        
    @track stats;                
    @track stageOptions  = [];   
    searchKeyword  = '';
    selectedStage  = '';
    minAmount      = null;
    maxAmount      = null;
    sortField      = 'LastModifiedDate';
    sortDirection  = 'DESC';
    pageNumber    = 1;
    totalPages    = 1;
    totalRecords  = 0;
    selectedRecordId;
    inlineStage = '';
    _selectedIds = new Set();
    newTaskSubject  = '';
    newTaskDueDate  = '';
    bulkTargetStage = '';
    isLoading      = false;
    isCreatingTask = false;
    _searchTimer;
    connectedCallback() {
        this._loadStageOptions();   
        this.loadData();            
    }

    async _loadStageOptions() {
        try {
            const raw = await getStagePicklistValues();
            this.stageOptions = [
                { label: '— All Stages —', value: '' },
                ...raw.map(opt => ({ label: opt.label, value: opt.value }))
            ];
        } catch (err) {
            console.error('Stage options load error:', err);
        }
    }
    async loadData() {
        this.isLoading = true;

        try {
            const response = await getWorkspaceData({
                searchKeyword : this.searchKeyword,
                stages        : this.selectedStage ? [this.selectedStage] : [],
                minAmount     : this.minAmount,
                maxAmount     : this.maxAmount,
                pageSize      : PAGE_SIZE,
                pageNumber    : this.pageNumber,
                sortField     : this.sortField,
                sortDirection : this.sortDirection
            });
            this.totalRecords = response.totalRecords;
            this.totalPages   = response.totalPages || 1;
            this.stats        = response.stats;
            const enriched = (response.records || []).map(rec => {
                return {
                    ...rec,
                    isSelected       : this._selectedIds.has(rec.oppId),
                    formattedAmount  : this._formatCurrency(rec.amount),
                    formattedCloseDate: this._formatDate(rec.closeDate),
                    tileClass        : this._getTileClass(rec),
                    healthClass      : this._getHealthClass(rec.healthLabel)
                };
            });

            this.records = enriched;

        } catch (err) {
            this._showToast('Error', err.body?.message || err.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleSearch(event) {
        window.clearTimeout(this._searchTimer);
        const value = event.target.value;
        this._searchTimer = setTimeout(() => {
            this.searchKeyword = value;
            this.pageNumber    = 1;
            this.loadData();
        }, DEBOUNCE_DELAY);
    }

    handleStageChange(event) {
        this.selectedStage = event.detail.value;
    }

    handleMinAmount(event) {
        this.minAmount = event.target.value ? Number(event.target.value) : null;
    }

    handleMaxAmount(event) {
        this.maxAmount = event.target.value ? Number(event.target.value) : null;
    }

    handleSortChange(event) {
        this.sortField = event.detail.value;
    }

    setSortAsc() {
        this.sortDirection = 'ASC';
    }

    setSortDesc() {
        this.sortDirection = 'DESC';
    }
    applyFilters() {
        this.pageNumber = 1;
        this.loadData();
    }
    clearFilters() {
        this.searchKeyword = '';
        this.selectedStage = '';
        this.minAmount     = null;
        this.maxAmount     = null;
        this.sortField     = 'LastModifiedDate';
        this.sortDirection = 'DESC';
        this.pageNumber    = 1;
        const searchInput = this.template.querySelector('lightning-input');
        if (searchInput) { searchInput.value = ''; }

        this.loadData();
    }

    async handleTileClick(event) {
        if (event.target.type === 'checkbox') { return; }

        const oppId = event.currentTarget.dataset.id;

        try {
            this.selectedRecordId = oppId;
            this.inlineStage      = '';

            this.detailRecord = await getOpportunityDetails({
                opportunityId: oppId
            });

            this.inlineStage =
            this.detailRecord.opportunityRecord.StageName;
            this.detailRecord = {
                ...this.detailRecord,
                contacts: this.detailRecord.contacts.map(c => ({
                    ...c,
                    initials: this._getInitials(c.Name)
                }))
            };

        } catch (err) {
            this._showToast('Error', err.body?.message || err.message, 'error');
        }
    }

    handleCheckboxClick(event) {
        event.stopPropagation();

        const oppId = event.currentTarget.dataset.id
                   || event.target.dataset.id;
        if (!oppId) { return; }

        if (this._selectedIds.has(oppId)) {
            this._selectedIds.delete(oppId);
        } else {
            this._selectedIds.add(oppId);
        }
        this.records = this.records.map(rec => ({
            ...rec,
            isSelected : this._selectedIds.has(rec.oppId),
            tileClass  : this._getTileClass({
                ...rec,
                isSelected: this._selectedIds.has(rec.oppId)
            })
        }));
    }

    clearBulkSelection() {
        this._selectedIds.clear();
        this.bulkTargetStage = '';
        this.records = this.records.map(rec => ({
            ...rec,
            isSelected : false,
            tileClass  : this._getTileClass({ ...rec, isSelected: false })
        }));
    }
    handleTaskSubjectChange(event) {
        this.newTaskSubject = event.target.value;
    }

    handleTaskDueDateChange(event) {
        this.newTaskDueDate = event.target.value;
    }

    async handleCreateTask() {
        if (!this.selectedRecordId) {
            this._showToast('Warning', 'Please select an opportunity first.', 'warning');
            return;
        }

        this.isCreatingTask = true;

        try {
            const response = await createFollowUpTask({
                opportunityId : this.selectedRecordId,
                subject       : this.newTaskSubject || 'Procurement Follow-up',
                dueDate       : this.newTaskDueDate || new Date().toISOString().split('T')[0]
            });

            if (response.success) {
                this._showToast('Success', response.message, 'success');

                this.newTaskSubject = '';
                this.newTaskDueDate = '';

                this._refreshDetailPanel();
            }

        } catch (err) {
            this._showToast('Error', err.body?.message || err.message, 'error');
        } finally {
            this.isCreatingTask = false;
        }
    }
    handleInlineStageChange(event) {
        this.inlineStage = event.detail.value;
    }
    async handleSaveStage() {
        if (!this.selectedRecordId || !this.inlineStage) { return; }

        try {
            const resp = await bulkUpdateStage({
                updateRequests: [{
                    oppId    : this.selectedRecordId,
                    newStage : this.inlineStage,
                    note     : 'Stage updated via Procurement Workspace'
                }]
            });

            if (resp.failureCount === 0) {
                this._showToast('Success', 'Stage updated successfully.', 'success');
                this._refreshDetailPanel();
                this.loadData();
            } else {
                this._showToast('Error', resp.errors.join('; '), 'error');
            }

        } catch (err) {
            this._showToast('Error', err.body?.message || err.message, 'error');
        }
    }


    handleBulkStageChange(event) {
        this.bulkTargetStage = event.detail.value;
    }

    async handleBulkUpdate() {
        if (this._selectedIds.size === 0) {
            this._showToast('Warning', 'No opportunitie+s selected.', 'warning');
            return;
        }
        if (!this.bulkTargetStage) {
            this._showToast('Warning', 'Please choose a target stage.', 'warning');
            return;
        }

        const updateRequests = [...this._selectedIds].map(id => ({
            oppId    : id,
            newStage : this.bulkTargetStage,
            note     : 'Bulk stage update from Procurement Workspace'
        }));

        try {
            const resp = await bulkUpdateStage({ updateRequests });

            const msg = `Updated: ${resp.successCount} | Failed: ${resp.failureCount}`;
            const variant = resp.failureCount === 0 ? 'success' : 'warning';
            this._showToast('Bulk Update Complete', msg, variant);

            if (resp.errors && resp.errors.length > 0) {
                resp.errors.forEach(e => console.error('Bulk error:', e));
            }

            this.clearBulkSelection();
            this.loadData();

        } catch (err) {
            this._showToast('Error', err.body?.message || err.message, 'error');
        }
    }

    goToPrevPage() {
        if (this.pageNumber > 1) {
            this.pageNumber--;
            this.loadData();
        }
    }

    goToNextPage() {
        if (this.pageNumber < this.totalPages) {
            this.pageNumber++;
            this.loadData();
        }
    }

    get isEmpty()         { return !this.isLoading && this.records.length === 0; }
    get showPagination()  { return this.totalPages > 1; }
    get isFirstPage()     { return this.pageNumber <= 1; }
    get isLastPage()      { return this.pageNumber >= this.totalPages; }
    get hasBulkSelection(){ return this._selectedIds.size > 0; }

    get bulkSelectionLabel() {
        return `${this._selectedIds.size} record(s) selected`;
    }

    get ascVariant()  { return this.sortDirection === 'ASC'  ? 'brand' : 'neutral'; }
    get descVariant() { return this.sortDirection === 'DESC' ? 'brand' : 'neutral'; }

    get sortOptions() {
        return [
            { label: 'Last Modified', value: 'LastModifiedDate' },
            { label: 'Name',          value: 'Name'             },
            { label: 'Amount',        value: 'Amount'           },
            { label: 'Close Date',    value: 'CloseDate'        },
            { label: 'Stage',         value: 'StageName'        }
        ];
    }
    get formattedPipeline() {
        return this.stats
            ? this._formatCurrency(this.stats.totalPipeline)
            : '—';
    }

    get formattedAvgDeal() {
        return this.stats
            ? this._formatCurrency(this.stats.avgDealSize)
            : '—';
    }

    get formattedDetailAmount() {
        return this.detailRecord
            ? this._formatCurrency(
                  this.detailRecord.opportunityRecord.Amount
              )
            : '—';
    }

    async _refreshDetailPanel() {
        if (!this.selectedRecordId) { return; }

        try {
            const fresh = await getOpportunityDetails({
                opportunityId: this.selectedRecordId
            });

            this.detailRecord = {
                ...fresh,
                contacts: fresh.contacts.map(c => ({
                    ...c,
                    initials: this._getInitials(c.Name)
                }))
            };

        } catch (err) {
            console.error('Detail refresh error:', err);
        }
    }

    _getTileClass(rec) {
        let cls = 'tile';
        if (rec.isSelected) { cls += ' tile-selected'; }
        if (rec.isOverdue)  { cls += ' tile-overdue';  }
        return cls;
    }

    _getHealthClass(label) {
        const map = { Hot: 'healthBadge hot', Warm: 'healthBadge warm', Cold: 'healthBadge cold' };
        return map[label] || 'healthBadge';
    }

    _formatCurrency(value) {
        if (value == null) { return '—'; }
        return CURRENCY_FORMATTER.format(value);
    }
    _formatDate(dateStr) {
        if (!dateStr) { return '—'; }
        return new Date(dateStr).toLocaleDateString('en-US', {
            year: 'numeric', month: 'short', day: 'numeric'
        });
    }

    _getInitials(name) {
        if (!name) { return '?'; }
        return name
            .split(' ')
            .filter(Boolean)
            .slice(0, 2)
            .map(n => n[0].toUpperCase())
            .join('');
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}
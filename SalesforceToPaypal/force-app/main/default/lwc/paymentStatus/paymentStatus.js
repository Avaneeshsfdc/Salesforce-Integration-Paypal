import { LightningElement, api, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPaymentStatus from '@salesforce/apex/PayPalService.getPaymentStatus';
import refundPayment from '@salesforce/apex/PayPalService.refundPayment';

export default class PaymentStatus extends LightningElement {
    @api orderId;
    @track paymentData;
    @track isLoading = false;
    @track showRefundModal = false;
    @track refundAmount = '';
    @track isRefunding = false;
    @track error;

    wiredPaymentResult;

    @wire(getPaymentStatus, { orderId: '$orderId' })
    wiredPayment(result) {
        this.wiredPaymentResult = result;
        if (result.data) {
            this.paymentData = result.data;
            this.error = null;
        } else if (result.error) {
            this.error = result.error;
            this.paymentData = null;
            this.showToast('Error', 'Failed to load payment status', 'error');
        }
    }

    refreshPaymentStatus() {
        this.isLoading = true;
        return refreshApex(this.wiredPaymentResult)
            .then(() => {
                this.showToast('Success', 'Payment status refreshed', 'success');
            })
            .catch(error => {
                this.showToast('Error', 'Failed to refresh payment status', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleRefundClick() {
        this.refundAmount = this.paymentData.Amount__c.toString();
        this.showRefundModal = true;
    }

    handlePartialRefundClick() {
        this.refundAmount = '';
        this.showRefundModal = true;
    }

    closeRefundModal() {
        this.showRefundModal = false;
        this.refundAmount = '';
        this.isRefunding = false;
    }

    handleRefundAmountChange(event) {
        this.refundAmount = event.target.value;
    }

    async processRefund() {
        if (!this.refundAmount || parseFloat(this.refundAmount) <= 0) {
            this.showToast('Error', 'Please enter a valid refund amount', 'error');
            return;
        }

        if (parseFloat(this.refundAmount) > this.paymentData.Amount__c) {
            this.showToast('Error', 'Refund amount cannot exceed the original payment amount', 'error');
            return;
        }

        this.isRefunding = true;

        try {
            await refundPayment({
                orderId: this.orderId,
                refundAmount: parseFloat(this.refundAmount),
                currencyCode: this.paymentData.Currency_Code__c
            });

            this.showToast('Success', 'Refund processed successfully', 'success');
            this.closeRefundModal();
            this.refreshPaymentStatus();

        } catch (error) {
            console.error('Refund error:', error);
            this.showToast('Error', 'Refund failed: ' + (error.body?.message || error.message), 'error');
        } finally {
            this.isRefunding = false;
        }
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }

    get statusVariant() {
        if (!this.paymentData) return 'base-autocomplete';
        
        switch (this.paymentData.Status__c) {
            case 'Completed':
                return 'success';
            case 'Failed':
            case 'Cancelled':
                return 'error';
            case 'Created':
            case 'Approved':
                return 'warning';
            case 'Refunded':
            case 'Partially Refunded':
                return 'info';
            default:
                return 'base-autocomplete';
        }
    }

    get statusIcon() {
        if (!this.paymentData) return 'utility:clock';
        
        switch (this.paymentData.Status__c) {
            case 'Completed':
                return 'utility:success';
            case 'Failed':
            case 'Cancelled':
                return 'utility:error';
            case 'Created':
            case 'Approved':
                return 'utility:clock';
            case 'Refunded':
            case 'Partially Refunded':
                return 'utility:undo';
            default:
                return 'utility:info';
        }
    }

    get canRefund() {
        return this.paymentData && 
               (this.paymentData.Status__c === 'Completed' || 
                this.paymentData.Status__c === 'Partially Refunded');
    }

    get canPartialRefund() {
        return this.paymentData && this.paymentData.Status__c === 'Completed';
    }

    get formattedAmount() {
        if (!this.paymentData) return '';
        return `${this.paymentData.Currency_Code__c} ${this.paymentData.Amount__c}`;
    }

    get formattedDate() {
        if (!this.paymentData) return '';
        return new Intl.DateTimeFormat('en-US', {
            year: 'numeric',
            month: 'long',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        }).format(new Date(this.paymentData.CreatedDate));
    }

    get formattedLastModified() {
        if (!this.paymentData) return '';
        return new Intl.DateTimeFormat('en-US', {
            year: 'numeric',
            month: 'long',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        }).format(new Date(this.paymentData.LastModifiedDate));
    }

    get maxRefundAmount() {
        return this.paymentData ? this.paymentData.Amount__c : 0;
    }

    get isValidRefundAmount() {
        if (!this.refundAmount) return false;
        const amount = parseFloat(this.refundAmount);
        return amount > 0 && amount <= this.maxRefundAmount;
    }
}
import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import createOrder from '@salesforce/apex/PayPalService.createOrder';
import captureOrder from '@salesforce/apex/PayPalService.captureOrder';
import getAuthStatus from '@salesforce/apex/PayPalAuthManager.getAuthStatus';

const ACCOUNT_FIELDS = ['Account.Id', 'Account.Name'];

export default class PaymentForm extends LightningElement {
    @api recordId;
    @track amount = '';
    @track description = '';
    @track currencyCode = 'USD';
    @track isLoading = false;
    @track showPayPalButtons = false;
    @track paypalOrderId = '';
    @track authStatus = {};

    currencyOptions = [
        { label: 'USD - US Dollar', value: 'USD' },
        { label: 'EUR - Euro', value: 'EUR' },
        { label: 'GBP - British Pound', value: 'GBP' },
        { label: 'CAD - Canadian Dollar', value: 'CAD' },
        { label: 'AUD - Australian Dollar', value: 'AUD' },
        { label: 'JPY - Japanese Yen', value: 'JPY' }
    ];

    @wire(getRecord, { recordId: '$recordId', fields: ACCOUNT_FIELDS })
    account;

    connectedCallback() {
        this.loadAuthStatus();
        this.loadPayPalScript();
    }

    async loadAuthStatus() {
        try {
            this.authStatus = await getAuthStatus();
        } catch (error) {
            console.error('Error loading auth status:', error);
            this.showToast('Error', 'Failed to load authentication status', 'error');
        }
    }

    loadPayPalScript() {
        if (window.paypal) {
            return;
        }

        const script = document.createElement('script');
        script.src = 'https://www.paypal.com/sdk/js?client-id=YOUR_CLIENT_ID&currency=USD,EUR,GBP,CAD,AUD,JPY';
        script.onload = () => {
            console.log('PayPal SDK loaded');
        };
        script.onerror = () => {
            this.showToast('Error', 'Failed to load PayPal SDK', 'error');
        };
        document.head.appendChild(script);
    }

    handleAmountChange(event) {
        this.amount = event.target.value;
        this.validateForm();
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
        this.validateForm();
    }

    handleCurrencyChange(event) {
        this.currencyCode = event.target.value;
    }

    validateForm() {
        const isValid = this.amount && 
                       parseFloat(this.amount) > 0 && 
                       this.description && 
                       this.description.trim().length > 0;
        
        this.showPayPalButtons = isValid;
        
        if (isValid && window.paypal) {
            this.renderPayPalButtons();
        }
    }

    renderPayPalButtons() {
        const paypalButtonContainer = this.template.querySelector('[data-id="paypal-button-container"]');
        if (!paypalButtonContainer || !window.paypal) {
            return;
        }

        paypalButtonContainer.innerHTML = '';

        window.paypal.Buttons({
            style: {
                layout: 'vertical',
                color: 'gold',
                shape: 'rect',
                label: 'paypal'
            },
            createOrder: async () => {
                try {
                    this.isLoading = true;
                    const orderResponse = await createOrder({
                        amount: parseFloat(this.amount),
                        currencyCode: this.currencyCode,
                        description: this.description,
                        accountId: this.recordId
                    });
                    
                    this.paypalOrderId = orderResponse.id;
                    return orderResponse.id;
                } catch (error) {
                    console.error('Error creating order:', error);
                    this.showToast('Error', 'Failed to create payment order: ' + error.body?.message, 'error');
                    throw error;
                } finally {
                    this.isLoading = false;
                }
            },
            onApprove: async (data) => {
                try {
                    this.isLoading = true;
                    const captureResponse = await captureOrder({
                        orderId: data.orderID
                    });
                    
                    this.showToast('Success', 'Payment completed successfully!', 'success');
                    this.resetForm();
                    this.dispatchEvent(new CustomEvent('paymentcomplete', {
                        detail: {
                            orderId: data.orderID,
                            captureResponse: captureResponse
                        }
                    }));
                } catch (error) {
                    console.error('Error capturing payment:', error);
                    this.showToast('Error', 'Payment capture failed: ' + error.body?.message, 'error');
                } finally {
                    this.isLoading = false;
                }
            },
            onError: (err) => {
                console.error('PayPal error:', err);
                this.showToast('Error', 'PayPal payment failed', 'error');
                this.isLoading = false;
            },
            onCancel: (data) => {
                console.log('Payment cancelled:', data);
                this.showToast('Info', 'Payment was cancelled', 'info');
                this.isLoading = false;
            }
        }).render(paypalButtonContainer);
    }

    resetForm() {
        this.amount = '';
        this.description = '';
        this.currencyCode = 'USD';
        this.showPayPalButtons = false;
        this.paypalOrderId = '';
        
        const paypalButtonContainer = this.template.querySelector('[data-id="paypal-button-container"]');
        if (paypalButtonContainer) {
            paypalButtonContainer.innerHTML = '';
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

    get accountName() {
        return this.account?.data?.fields?.Name?.value || 'Unknown';
    }

    get isFormValid() {
        return this.amount && 
               parseFloat(this.amount) > 0 && 
               this.description && 
               this.description.trim().length > 0;
    }

    get isPayPalReady() {
        return window.paypal && this.authStatus.isAuthenticated;
    }

    get loadingMessage() {
        return this.isLoading ? 'Processing payment...' : '';
    }
}
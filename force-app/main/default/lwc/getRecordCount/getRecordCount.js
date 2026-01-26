import { LightningElement, track, wire } from 'lwc';
import getAccessibleRecordCounts from '@salesforce/apex/UserAccessCountService.getAccessibleRecordCounts';
import getSupportedObjects from '@salesforce/apex/UserAccessCountService.getSupportedObjects';

export default class UserAccessCount extends LightningElement {
    userId;
    selectedObjects = [];
    results;
    objectMetadata = {}; // map of apiName => ObjectOWDInfo
    objectOptions = [];
    showOwdWarning = false;

    columns = [
        { label: 'Object', fieldName: 'object' },
        { label: 'Accessible Record Count', fieldName: 'count', type: 'number' }
    ];

    // Load objects dynamically on init
    connectedCallback() {
        this.loadObjects();
    }

    loadObjects() {
        getSupportedObjects()
            .then(objects => {
                this.objectOptions = objects.map(obj => ({ label: obj.label, value: obj.apiName }));
                // store metadata for OWD checks
                objects.forEach(obj => {
                    this.objectMetadata[obj.apiName] = obj;
                });
            })
            .catch(error => {
                console.error('Error loading objects: ', error);
            });
    }

    handleUserChange(event) {
        this.userId = event.target.value;
    }

    handleObjectChange(event) {
        this.selectedObjects = event.detail.value;
        this.checkOwdWarning();
    }

    checkOwdWarning() {
        this.showOwdWarning = this.selectedObjects.some(apiName => {
            let obj = this.objectMetadata[apiName];
            return obj && obj.owd !== 'Private';
        });
    }

    fetchCounts() {
        if (!this.userId || this.selectedObjects.length === 0) return;

        getAccessibleRecordCounts({
            userId: this.userId,
            objectApiNames: this.selectedObjects
        })
        .then(res => {
            this.results = Object.keys(res).map(key => ({
                object: key,
                count: res[key]
            }));
        })
        .catch(error => {
            console.error(error);
        });
    }
}
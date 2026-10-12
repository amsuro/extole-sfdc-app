public with sharing class ExtolePersonAccounts {
    @AuraEnabled(cacheable=true)
    public static Boolean isEnabled() {
        return Schema.sObjectType.Account.fields.getMap().containsKey('ispersonaccount');
    }
}

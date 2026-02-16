public with sharing class UserAccessCountService {
    
    private static final Integer MAX_QUERY_LIMIT = 20000; // prevent runaway queries
    
    @AuraEnabled(cacheable=false)
    public static Map<String, Integer> getAccessibleRecordCounts(
        Id userId,
        List<String> objectApiNames
    ) {
        if (userId == null || objectApiNames == null || objectApiNames.isEmpty()) {
            throw new AuraHandledException('UserId and objectApiNames are required');
        }
        
        Map<String, Integer> result = new Map<String, Integer>();
        
        // --- Step 1: Principals for share-based access ---
        Set<Id> principalIds = new Set<Id>();
        principalIds.add(userId);
        
        // Public groups, queues, and indirect memberships
        principalIds.addAll(PublicGroupResolver.getAllPublicGroupsForUser(userId));
        
        // Subordinate users via role hierarchy
        Set<Id> subordinateUserIds = getSubordinateUsers(userId);
        
        // --- Step 2: Iterate objects and count accessible records ---
        for (String objApi : objectApiNames) {
            Integer countVal = 0;
            
            // Owned by user
            try {
                String ownerQuery = 'SELECT COUNT() FROM ' + objApi + ' WHERE OwnerId = :userId ' ;
                countVal += Database.countQuery(ownerQuery);
            } catch (Exception ex) {
                // Object may not exist or not be queryable
            }
            
            // Shared via share table
            try {
                String shareQuery = 'SELECT COUNT() FROM ' + objApi + 'Share WHERE UserOrGroupId IN :principalIds  ' ;
                countVal += Database.countQuery(shareQuery);
            } catch (Exception ex) {
                // No share object or not accessible
            }
            
            // Role hierarchy / subordinate users
            if (!subordinateUserIds.isEmpty()) {
                try {
                    String subQuery = 'SELECT COUNT() FROM ' + objApi + ' WHERE OwnerId IN :subordinateUserIds ';
                    countVal += Database.countQuery(subQuery);
                } catch (Exception ex) {
                    // ignore
                }
            }
            
            // ControlledByParent records
            try {
                String ctrlByParentQuery = 'SELECT COUNT() FROM ' + objApi + ' WHERE IsDeleted = false AND Id IN ' +
                    '(SELECT ChildRecordId FROM ' + objApi + 'Share WHERE UserOrGroupId = :principalIds) ' ;
                countVal += Database.countQuery(ctrlByParentQuery);
            } catch (Exception ex) {
                // ignore
            }
            
            
            result.put(objApi, countVal);
        }
        
        return result;
    }
    
    // --- Helper: get subordinate users via role hierarchy ---
    private static Set<Id> getSubordinateUsers(Id userId) {
        Set<Id> subUserIds = new Set<Id>();
        
        User u = [SELECT UserRoleId FROM User WHERE Id = :userId];
        if (u.UserRoleId == null) return subUserIds;
        
        // BFS to collect all subordinate roles
        Set<Id> roleIds = new Set<Id>{u.UserRoleId};
            Set<Id> toProcess = new Set<Id>{u.UserRoleId};
                
                while (!toProcess.isEmpty()) {
                    List<UserRole> children = [SELECT Id FROM UserRole WHERE ParentRoleId IN :toProcess];
                    toProcess.clear();
                    for (UserRole r : children) {
                        if (roleIds.add(r.Id)) toProcess.add(r.Id);
                    }
                }
        
        // Collect users in these roles
        for (User usr : [SELECT Id FROM User WHERE UserRoleId IN :roleIds AND Id != :userId]) {
            subUserIds.add(usr.Id);
        }
        
        return subUserIds;
    }
    
    // --- Object metadata for LWC (OWD, labels) ---
    @AuraEnabled(cacheable=true)
    public static List<ObjectOWDInfo> getSupportedObjects() {
        List<ObjectOWDInfo> objects = new List<ObjectOWDInfo>();
        
        List<EntityDefinition> objDefs = [
            SELECT DeveloperName, Label, InternalSharingModel, ExternalSharingModel, IsCustomizable, IsQueryable
            FROM EntityDefinition
            WHERE IsCustomizable = true AND IsQueryable = true
        ];
        
        for (EntityDefinition ed : objDefs) {
            String owd = String.valueOf(ed.InternalSharingModel);
            objects.add(new ObjectOWDInfo(ed.DeveloperName, ed.Label, owd));
        }
        
        objects.sort();
        return objects;
    }
    
    // --- Wrapper for object metadata ---
    public class ObjectOWDInfo implements Comparable {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String owd;
        @AuraEnabled public Boolean isPrivate;
        
        public ObjectOWDInfo(String apiName, String label, String owd) {
            this.apiName = apiName;
            this.label = label;
            this.owd = owd;
            this.isPrivate = (owd == 'Private');
        }
        
        public Integer compareTo(Object compareTo) {
            ObjectOWDInfo other = (ObjectOWDInfo)compareTo;
            return this.label.toLowerCase().compareTo(other.label.toLowerCase());
        }
    }
}
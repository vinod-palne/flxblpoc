public with sharing class PublicGroupResolver {

    /**
     * Returns all public groups the user belongs to (direct and nested)
     */
    public static Set<Id> getAllPublicGroupsForUser(Id userId) {
        Set<Id> visitedGroupIds = new Set<Id>();
        Set<Id> toProcess = new Set<Id>();

        // Direct memberships
        for (GroupMember gm : [SELECT GroupId FROM GroupMember WHERE UserOrGroupId = :userId]) {
            toProcess.add(gm.GroupId);
        }

        // Traverse nested groups
        while (!toProcess.isEmpty()) {
            Set<Id> nextLevel = new Set<Id>();
            for (GroupMember gm : [SELECT GroupId, UserOrGroupId FROM GroupMember WHERE UserOrGroupId IN :toProcess]) {
                if (!visitedGroupIds.contains(gm.GroupId)) {
                    visitedGroupIds.add(gm.GroupId);
                    nextLevel.add(gm.GroupId);
                }
            }
            toProcess = nextLevel;
        }

        return visitedGroupIds;
    }
}
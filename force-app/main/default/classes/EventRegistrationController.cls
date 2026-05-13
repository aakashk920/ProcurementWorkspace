
public with sharing class EventRegistrationController {
    public class CampaignWrapper {
        @AuraEnabled public String  id          { get; set; }
        @AuraEnabled public String  name        { get; set; }
        @AuraEnabled public String  status      { get; set; }
        @AuraEnabled public String  description { get; set; }
        @AuraEnabled public Date    startDate   { get; set; }
        @AuraEnabled public Date    endDate     { get; set; }
        @AuraEnabled public Integer memberCount { get; set; }

        public CampaignWrapper(Campaign c, Integer count) {
            this.id          = c.Id;
            this.name        = c.Name;
            this.status      = c.Status;
            this.description = c.Description;
            this.startDate   = c.StartDate;
            this.endDate     = c.EndDate;
            this.memberCount = count;
        }
    }

    public class RegistrationResult {
        @AuraEnabled public Boolean success           { get; set; }
        @AuraEnabled public String  message           { get; set; }
        @AuraEnabled public String  campaignMemberId  { get; set; }
        @AuraEnabled public String  qrCodeUrl         { get; set; }
        @AuraEnabled public String  contactId         { get; set; }

        public RegistrationResult(Boolean success, String message) {
            this.success = success;
            this.message = message;
        }
    }

    public class ContactFormInput {
        @AuraEnabled public String firstName  { get; set; }
        @AuraEnabled public String lastName   { get; set; }
        @AuraEnabled public String email      { get; set; }
        @AuraEnabled public String phone      { get; set; }
        @AuraEnabled public String title      { get; set; }
        @AuraEnabled public String campaignId { get; set; }
    }
    public class CheckInResult {
        @AuraEnabled public Boolean success          { get; set; }
        @AuraEnabled public String  message          { get; set; }
        @AuraEnabled public String  attendeeName     { get; set; }
        @AuraEnabled public String  campaignName     { get; set; }
        @AuraEnabled public String  checkInTime      { get; set; }
        @AuraEnabled public Boolean alreadyCheckedIn { get; set; }

        public CheckInResult(Boolean success, String message) {
            this.success = success;
            this.message = message;
            this.alreadyCheckedIn = false;
        }
    }
    @AuraEnabled(cacheable=true)
    public static List<CampaignWrapper> getActiveCampaigns() {
        try {
            List<CampaignWrapper> results = new List<CampaignWrapper>();

            List<Campaign> campaigns = [
                SELECT Id, Name, Status, Description, StartDate, EndDate,
                       NumberOfContacts
                FROM   Campaign
                WHERE  Status IN ('Planned', 'In Progress')
                ORDER  BY StartDate ASC
                LIMIT  50
            ];

            if (campaigns.isEmpty()) {
                return results;
            }

            Map<Id, Integer> memberCountMap = new Map<Id, Integer>();
            for (AggregateResult ar : [
                SELECT CampaignId, COUNT(Id) memberCount
                FROM   CampaignMember
                WHERE  CampaignId IN :campaigns
                GROUP  BY CampaignId
            ]) {
                memberCountMap.put(
                    (Id) ar.get('CampaignId'),
                    (Integer) ar.get('memberCount')
                );
            }

            for (Campaign c : campaigns) {
                Integer cnt = memberCountMap.containsKey(c.Id)
                              ? memberCountMap.get(c.Id)
                              : 0;
                results.add(new CampaignWrapper(c, cnt));
            }

            return results;

        } catch (Exception e) {
            throw new AuraHandledException(
                'Error fetching campaigns: ' + e.getMessage()
            );
        }
    }

    @AuraEnabled
    public static RegistrationResult registerAttendee(ContactFormInput input) {
        RegistrationResult result = new RegistrationResult(false, '');

        if (String.isBlank(input.firstName) || String.isBlank(input.lastName)) {
            result.message = 'First name and Last name are required.';
            return result;
        }
        if (String.isBlank(input.email) || !input.email.contains('@')) {
            result.message = 'A valid email address is required.';
            return result;
        }
        if (String.isBlank(input.campaignId)) {
            result.message = 'Please select a Campaign.';
            return result;
        }


        Campaign camp;
        try {
            camp = [
                SELECT Id, Name, StartDate, EndDate, Status
                FROM   Campaign
                WHERE  Id = :input.campaignId
                LIMIT  1
            ];
        } catch (Exception e) {
            result.message = 'Campaign not found. Please refresh and try again.';
            return result;
        }

        Contact con = new Contact();
        List<Contact> existingContacts = [
            SELECT Id, FirstName, LastName, Email
            FROM   Contact
            WHERE  Email = :input.email
            LIMIT  1
        ];

        if (!existingContacts.isEmpty()) {
            con = existingContacts[0];
            con.FirstName = input.firstName;
            con.LastName  = input.lastName;
            con.Phone     = input.phone;
            con.Title     = input.title;
            update con;
        } else {
            con.FirstName = input.firstName;
            con.LastName  = input.lastName;
            con.Email     = input.email;
            con.Phone     = input.phone;
            con.Title     = input.title;
            insert con;
        }
        result.contactId = con.Id;

        List<CampaignMember> existingMembers = [
            SELECT Id, Status, Is_Checked_In__c
            FROM   CampaignMember
            WHERE  CampaignId = :camp.Id
            AND    ContactId  = :con.Id
            LIMIT  1
        ];

        if (!existingMembers.isEmpty()) {
            result.message = 'You are already registered for this event!';
            result.success = false;
            return result;
        }

        CampaignMember cm = new CampaignMember();
        cm.CampaignId        = camp.Id;
        cm.ContactId         = con.Id;
        cm.Status            = 'Registered';
        cm.Is_Checked_In__c  = false;
        insert cm;

        result.campaignMemberId = cm.Id;
        String qrData = cm.Id + '|' + camp.Name + '|' + camp.StartDate;
        String cmQrUrl =
            'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=' +
            EncodingUtil.urlEncode(qrData, 'UTF-8');

        result.qrCodeUrl = cmQrUrl;
        Boolean emailSent = sendRegistrationEmail(
            con,
            camp,
            cm,
            cmQrUrl
        );

        if (!emailSent) {
            result.success = true;
            result.message = 'Registered successfully! However, confirmation email could not be sent.';
            return result;
        }

        result.success = true;
        result.message = 'Registration successful! Check your email for the QR code.';
        return result;
    }

    private static Boolean sendRegistrationEmail(
        Contact con,
        Campaign camp,
        CampaignMember cm,
        String qrUrl
    ) {
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

            mail.setToAddresses(new List<String>{ con.Email });
            mail.setSubject('Registration Confirmed — ' + camp.Name);
            mail.setWhatId(camp.Id);
            mail.setTargetObjectId(con.Id);
            mail.setSaveAsActivity(true);

            String startDateStr = camp.StartDate != null
                ? camp.StartDate.format()
                : 'TBD';
            String endDateStr = camp.EndDate != null
                ? camp.EndDate.format()
                : 'TBD';
            String attendeeName = con.FirstName + ' ' + con.LastName;

            String htmlBody =
                '<html><body style="font-family: Arial, sans-serif; color: #333;">' +

                '<div style="background-color:#1B74E4; padding:24px; text-align:center;">' +
                '<h1 style="color:#fff; margin:0;">🎉 You\'re Registered!</h1>' +
                '</div>' +

                '<div style="padding: 24px;">' +
                '<p style="font-size:16px;">Hi <strong>' + attendeeName + '</strong>,</p>' +
                '<p>You have successfully registered for the following event:</p>' +

                '<table style="border-collapse:collapse; width:100%; margin:16px 0;">' +
                '<tr style="background:#f4f6f9;">' +
                '<td style="padding:10px; font-weight:bold; width:40%;">Event Name</td>' +
                '<td style="padding:10px;">' + camp.Name + '</td>' +
                '</tr>' +
                '<tr>' +
                '<td style="padding:10px; font-weight:bold;">Start Date</td>' +
                '<td style="padding:10px;">' + startDateStr + '</td>' +
                '</tr>' +
                '<tr style="background:#f4f6f9;">' +
                '<td style="padding:10px; font-weight:bold;">End Date</td>' +
                '<td style="padding:10px;">' + endDateStr + '</td>' +
                '</tr>' +
                '<tr>' +
                '<td style="padding:10px; font-weight:bold;">Registration ID</td>' +
                '<td style="padding:10px; font-size:12px; color:#666;">' + cm.Id + '</td>' +
                '</tr>' +
                '</table>' +
                '<div style="text-align:center; margin:32px 0;">' +
                '<h2 style="color:#1B74E4;">Your Check-In QR Code</h2>' +
                '<p style="color:#666;">Please present this QR code at the event entrance for quick check-in.</p>' +
                '<img src="' + qrUrl + '" ' +
                '     alt="Check-In QR Code" ' +
                '     style="border:4px solid #1B74E4; border-radius:8px; padding:8px;" />' +
                '<p style="font-size:12px; color:#999; margin-top:8px;">Registration ID: ' + cm.Id + '</p>' +
                '</div>' +

                '<hr style="border:1px solid #eee;" />' +
                '<p style="font-size:12px; color:#999;">This is an automated confirmation. Please do not reply to this email.</p>' +
                '</div>' +

                '</body></html>';

            mail.setHtmlBody(htmlBody);

            List<Messaging.SendEmailResult> emailResults =
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);

            if (emailResults != null && !emailResults.isEmpty()) {
                return emailResults[0].isSuccess();
            }
            return false;

        } catch (Exception e) {
            System.debug('Email send error: ' + e.getMessage());
            return false;
        }
    }

    @AuraEnabled
    public static CheckInResult processCheckIn(String qrData) {
        CheckInResult result = new CheckInResult(false, '');

        if (String.isBlank(qrData)) {
            result.message = 'Invalid QR code. No data found.';
            return result;
        }

        List<String> parts = qrData.split('\\|');
        if (parts.size() < 1 || String.isBlank(parts[0])) {
            result.message = 'QR code format is invalid. Please use a valid event QR code.';
            return result;
        }

        String campaignMemberId = parts[0].trim();

        if (campaignMemberId.length() < 15) {
            result.message = 'QR code contains an invalid ID. Please try again.';
            return result;
        }

        List<CampaignMember> members;
        try {
            members = [
                SELECT Id,
                       ContactId,
                       Contact.FirstName,
                       Contact.LastName,
                       Contact.Email,
                       CampaignId,
                       Campaign.Name,
                       Campaign.StartDate,
                       Status,
                       Is_Checked_In__c,
                       Check_In_DateTime__c
                FROM   CampaignMember
                WHERE  Id = :campaignMemberId
                LIMIT  1
            ];
        } catch (Exception e) {
            result.message = 'Error reading QR data: ' + e.getMessage();
            return result;
        }

        if (members.isEmpty()) {
            result.message = 'No registration found for this QR code. Please verify your registration.';
            return result;
        }

        CampaignMember cm = members[0];
        if (cm.Is_Checked_In__c) {
            result.success          = true;
            result.alreadyCheckedIn = true;
            result.attendeeName     = cm.Contact.FirstName + ' ' + cm.Contact.LastName;
            result.campaignName     = cm.Campaign.Name;
            result.checkInTime      = cm.Check_In_DateTime__c != null
                                      ? String.valueOf(cm.Check_In_DateTime__c)
                                      : 'Previously checked in';
            result.message = '- ' + result.attendeeName + ' has already checked in for this event.';
            return result;
        }

        cm.Is_Checked_In__c       = true;
        cm.Check_In_DateTime__c   = DateTime.now();
        cm.Status                 = 'Attended';

        try {
            update cm;
        } catch (Exception e) {
            result.message = 'Check-in update failed: ' + e.getMessage();
            return result;
        }

        result.success      = true;
        result.attendeeName = cm.Contact.FirstName + ' ' + cm.Contact.LastName;
        result.campaignName = cm.Campaign.Name;
        result.checkInTime  = String.valueOf(cm.Check_In_DateTime__c);
        result.message      = ' Check-in successful! Welcome, ' + result.attendeeName + '!';

        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<CampaignMember> getCampaignMembers(String campaignId) {
        if (String.isBlank(campaignId)) {
            throw new AuraHandledException('Campaign ID is required.');
        }

        try {
            return [
                SELECT Id,
                       Contact.FirstName,
                       Contact.LastName,
                       Contact.Email,
                       Contact.Phone,
                       Status,
                       Is_Checked_In__c,
                       Check_In_DateTime__c
                FROM   CampaignMember
                WHERE  CampaignId = :campaignId
                ORDER  BY Contact.LastName ASC
                LIMIT  200
            ];
        } catch (Exception e) {
            throw new AuraHandledException(
                'Error fetching attendees: ' + e.getMessage()
            );
        }
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getCampaignStats(String campaignId) {
        Map<String, Integer> stats = new Map<String, Integer>{
            'totalRegistered' => 0,
            'totalCheckedIn'  => 0,
            'pendingCheckIn'  => 0
        };

        if (String.isBlank(campaignId)) {
            return stats;
        }

        try {
            stats.put('totalRegistered', [
                SELECT COUNT()
                FROM   CampaignMember
                WHERE  CampaignId = :campaignId
            ]);

            stats.put('totalCheckedIn', [
                SELECT COUNT()
                FROM   CampaignMember
                WHERE  CampaignId     = :campaignId
                AND    Is_Checked_In__c = true
            ]);

            stats.put(
                'pendingCheckIn',
                stats.get('totalRegistered') - stats.get('totalCheckedIn')
            );

        } catch (Exception e) {
            throw new AuraHandledException(
                'Error fetching stats: ' + e.getMessage()
            );
        }
        return stats;
    }

}
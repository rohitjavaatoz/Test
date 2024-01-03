package com.verizon.ucm.interactionmanagement.services;

import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.stream.Collectors;

import com.verizon.ucm.interactionmanagement.config.MailConnector;
import com.verizon.ucm.interactionmanagement.config.emailstatus.EmailStatusProperties;
import com.verizon.ucm.interactionmanagement.constants.Constants;
import com.verizon.ucm.interactionmanagement.dto.*;

import jakarta.activation.DataHandler;
import jakarta.activation.DataSource;
import jakarta.mail.internet.MimeBodyPart;
import jakarta.mail.internet.MimeMultipart;

import jakarta.mail.MessagingException;
import jakarta.mail.internet.MimeMessage;

import com.verizon.ucm.interactionmanagement.ifc.ReferenceIFC;
import com.verizon.ucm.interactionmanagement.ifc.UserLabelIfc;
import com.verizon.ucm.interactionmanagement.model.*;

import com.verizon.ucm.interactionmanagement.repository.*;
import com.verizon.ucm.interactionmanagement.response.EmailLockResponse;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Service;
import org.springframework.util.StopWatch;

import jakarta.mail.*;
import jakarta.mail.util.ByteArrayDataSource;

@Service
public class MailHandlingService {
	
	private static final Logger LOGGER = LoggerFactory.getLogger(MailHandlingService.class);

	@Autowired
	private EmailMessagesRepository emailMessagesRepository;
	@Autowired
	private EmailMessageTPMRequestRepository emailMessageTPMRequestRepository;
	@Autowired
	private TPMRequestNetworkElementsRepository tPMRequestNetworkElementsRepository;

	@Autowired
	private MessagesRepository messagesRepository;
	
	@Autowired
	private EmailAttachmentsRepository emailAttachmentsRepository;
	
	@Autowired
	private EmailMessageExtractionRepository emailMessageExtractionRepository;

	@Autowired
	private PartyRepository partyRepository;
	
	@Autowired
	private EmailMessageNetworkElementsRepository emailMessageNetworkElementsRepository;
	
	@Autowired
	private EquipmentValidationService equipmentValidationService;
	
	@Autowired
	private ExtractionConfidenceRepository extractionConfidenceRepository;

	@Autowired
	private EmailMessageExtractionAuditLogRepository emailMessageExtractionAuditLogRepository;

	@Autowired
	private EmailExtractionMappingRepository emailExtractionMappingRepository;

	@Autowired
	MessageRecipientCCRepository messageRecipientCCRepository;

	@Autowired
	MessageProcessingHistoryRepository messageProcessingHistoryRepository;

	@Autowired
	MailConnector mailConnector;

	@Autowired
	EmailMessageProcessingHistoryRepository emailMessageProcessingHistoryRepository;

	@Autowired
	MessageTypesService messageTypesService;
	@Autowired
	MessageStatusService messageStatusService;

	@Autowired
	EmailMessageStatusService emailMessageStatusService;

	@Autowired
	MessageRecipientRepository messageRecipientRepository;

	@Autowired
	EmailMessageLabelService emailMessageLabelService;

	@Autowired
	EmailMessageStatusRepository emailMessageStatusRepository;

	@Autowired
	EmailMessageLabelsRepository emailMessageLabelsRepository;
	@Autowired
	EmailMessageExtractionService emailMessageExtractionService;

	public List<MailMessageDTO> getMailMessages(Pageable pageable,UUID uuid){
		List<MailMessageDTO> mailMessageList = new ArrayList<>();
		Map<Integer,String> referenceIdMap = new HashMap<>();
		Map<Integer,BigInteger> extractionIdCountMap = new HashMap<>();
		List<Object[]> mailMessgeQueryList = emailMessagesRepository.getAllMailMessages(pageable);
		LOGGER.info("getMailMessages: Retrieved unprocessed email Messages raw list : {}, uuid={}",mailMessgeQueryList,uuid);
		List<Object[]> referenceIdmappingList = emailMessageExtractionRepository.getReferenceIds();
		LOGGER.info("getMailMessages: Retrieved List of reference IDs : {} , uuid={}",referenceIdmappingList,uuid);
//		List<EmailAttachments>  emailAttachments = emailAttachmentsRepository.getAllEmailAttachments();
//		LOGGER.info("getMailMessages: Retrieved all email attachments : {} , uuid={}",emailAttachments,uuid);
//		List<Integer> emailMessageIds = emailAttachments.stream().map(e->e.getEmailMessageId()).collect(Collectors.toList());
		List<Integer> emailMessageIds=emailAttachmentsRepository.getAllEmailMessageIds();
		List<Integer> emailExtractionIdsList = getExtIdsList(mailMessgeQueryList,"unprocessed");
		List<Integer> emailMessageIdsList = getEmailIdsList(mailMessgeQueryList,"unprocessed");
		Map<Object[],Integer> emailLabelsList = getEmailLabels(emailExtractionIdsList);
		Map<Object[],Integer> emailLabelsByIdList = getEmailLabelsById(emailMessageIdsList);
		Map<UserLabelIfc,Integer> userLabelsList = getUserLabelsList(emailMessageIdsList);
		List<Object[]> mappingCount =emailMessagesRepository.getExtractionMappingCount();
		LOGGER.info("getMailMessages: Number of email messages which contains child messages by Extraction ID: {} , uuid={}",mappingCount,uuid);
		//check for multiple reference ids for same email message id in future
		LOGGER.info("getMailMessages: Adding all unprocessed email messages to the response: uuid={}",uuid);
		referenceIdmappingList.stream().forEach(ref->{
		    	referenceIdMap.put((Integer)ref[1], (String)ref[2]);
		});
		Instant startTime = Instant.now();
		mappingCount.stream().forEach(ref-> extractionIdCountMap.put((Integer)ref[0], (BigInteger)ref[1]));
	    mailMessgeQueryList.stream().forEach(mail->{
	    	MailMessageDTO mailMessage = new MailMessageDTO();
	    	mailMessage.setEmailMessageId((Integer) mail[1]);
	    	if(mail[0] != null && extractionIdCountMap.containsKey(mail[0])) {
	         mailMessage.setEmailMessagesCount(extractionIdCountMap.get(mail[0]).subtract(BigInteger.ONE));
	    	}
	    	mailMessage.setSubject((String) mail[3]);
	    	mailMessage.setDateSent((Timestamp) mail[4]);
	    	mailMessage.setPartyName((String) mail[5]);
			mailMessage.setIsSeen((Boolean) mail[6]);
	    	if(emailMessageIds.contains((Integer)mail[1])) {
	    		mailMessage.setAttachmentPresent(true);
	    	}
	    	else {
	    		mailMessage.setAttachmentPresent(false);
	    	}
	    	if(referenceIdMap.containsKey((Integer)mail[0])){
	    		mailMessage.setReferenceId(referenceIdMap.get((Integer)mail[0]));
	    	}
			addLabelsProcessed(mail,mailMessage,emailLabelsList,emailLabelsByIdList,userLabelsList,"unprocessed");
	    	mailMessageList.add(mailMessage);

		});
		LOGGER.info("getMailMessages: Added all unprocessed email messages to the response : {}, uuid={}",mailMessageList,uuid);
		return mailMessageList;
	}

	private List<Integer> getEmailIdsList(List<Object[]> mailMessgeQueryList, String type) {
		List<Integer> emailMessageIdsList = new ArrayList<>();
		mailMessgeQueryList.stream().forEach(e->{
			Integer emailId = Objects.equals(type, "processed") ?(Integer) e[0]:(Integer) e[1];
			if(emailId!=null){
				emailMessageIdsList.add(emailId);
			}
		});
		return emailMessageIdsList;
	}

	private List<Integer> getExtIdsList(List<Object[]> mailMessgeQueryList, String type) {
		List<Integer> emailExtractionIdsList = new ArrayList<>();
		mailMessgeQueryList.stream().forEach(e->{
			Integer extractionId = Objects.equals(type, "processed") ?(Integer) e[8]:(Integer) e[0];
			if(extractionId!=null){
				emailExtractionIdsList.add(extractionId);
			}
		});
		return emailExtractionIdsList;
	}

	public Map<UserLabelIfc, Integer> getUserLabelsList(List<Integer> emailMessageIdsList) {
		List<UserLabelIfc> userLabelIfcList = emailMessagesRepository.getUserLabels(emailMessageIdsList);
		return userLabelIfcList.stream()
				.collect(Collectors.toMap(
						row -> row,
						row -> row.getEmailMessageId()
				));
	}

	public Map<Object[], Integer> getEmailLabelsById(List<Integer> emailMessageIdsList) {
		List<Object[]> emailLabelsByEmailId = emailMessagesRepository.getLabelByEmailIdList(emailMessageIdsList);
		return emailLabelsByEmailId.stream()
				.collect(Collectors.toMap(
						row -> row,
						row -> (Integer) row[0]
				));
	}

	public Map<Object[], Integer> getEmailLabels(List<Integer> emailExtractionIdsList) {
		List<Object[]> emailLabelsByExtId = emailMessagesRepository.getLabelsList(emailExtractionIdsList);
		return emailLabelsByExtId.stream()
				.collect(Collectors.toMap(
						row -> row,
						row -> (Integer) row[0]
				));
	}


	public List<MailMessageDTO> getMailMessagesByEmailExtractionId(Integer emailMessageId,UUID uuid){
//		Integer emailMessageExtractionId=emailMessageExtractionRepository.getEmailMessageExtractionIdByEmailMessageId(emailMessageId);
//		LOGGER.info("getMailMessagesByEmailExtractionId: Retrieved extraction ID {} of email message ID  : {}, uuid={}",emailMessageExtractionId,emailMessageId,uuid);
		List<Integer> emailMessageIdsRelated=emailMessageExtractionRepository.getAllEmailMessageIdsByEmailMessageExtractionId(emailMessageId);
		LOGGER.info("getMailMessagesByEmailExtractionId: Retrieved List of email message Id's by parent email Id : {},List of Id's={} , uuid={}",emailMessageId,emailMessageIdsRelated,uuid);
		List<MailMessageDTO> mailMessageList = new ArrayList<>();
		Map<Integer,String> referenceIdMap = new HashMap<>();
		List<Object[]> mailMessgeQueryList = emailMessagesRepository.getAllMailMessagesByCommmonExtractionId(emailMessageIdsRelated);
		LOGGER.info("getMailMessagesByEmailExtractionId: Retrieved List of email message details : {}, uuid={}",emailMessageIdsRelated,uuid);
		List<Object[]> referenceIdmappingList = emailMessageExtractionRepository.getReferenceIds();
		LOGGER.info("getMailMessagesByEmailExtractionId: Adding email message details to the response : uuid={}",uuid);
//		List<EmailAttachments>  emailAttachments = emailAttachmentsRepository.getAllEmailAttachments();
//		List<Integer> emailMessageIds = emailAttachments.stream().map(e->e.getEmailMessageId()).collect(Collectors.toList());
		List<Integer> emailMessageIds=emailAttachmentsRepository.getAllEmailMessageIds();
		referenceIdmappingList.stream().forEach(ref->{
		    	referenceIdMap.put((Integer)ref[1], (String)ref[2]);
		});
	    mailMessgeQueryList.stream().forEach(mail-> {
			MailMessageDTO mailMessage = null;
			if (!emailMessageId.equals((Integer) mail[0])) {
				mailMessage = new MailMessageDTO();
				mailMessage.setEmailMessageId((Integer) mail[0]);
				mailMessage.setSubject((String) mail[2]);
				mailMessage.setDateSent((Timestamp) mail[3]);
				mailMessage.setPartyName((String) mail[4]);
				mailMessage.setIsSeen((Boolean) mail[5]);
				if (emailMessageIds.contains((Integer) mail[0])) {
					mailMessage.setAttachmentPresent(true);
				} else {
					mailMessage.setAttachmentPresent(false);
				}
				if (referenceIdMap.containsKey((Integer) mail[0])) {
					mailMessage.setReferenceId(referenceIdMap.get((Integer) mail[0]));
				}

				LOGGER.info("getMailMessagesByEmailExtractionId: Retrieved email message by ID:{},emailMessage uuid={}",uuid);
				String emailMessageStatus = EmailStatusProperties.getMappingNameById((Integer) mail[6]);
				LOGGER.info("getMailMessagesByEmailExtractionId: Adding email message details to the response emailMessagesStatus={},emailMessageStatus: uuid={}",uuid);
				mailMessage.setEmailMessageStatus(findEmailType(mailMessage.getSubject(), emailMessageStatus));


			List<EmailLabelsResponse> emailLabelsResponses = new ArrayList<>();
			List<Object[]> emailLabels = emailMessagesRepository.getLabelByEmailMessageId(mailMessage.getEmailMessageId());
			emailLabels.stream().forEach(emailLabel -> {
				EmailLabelsResponse emailLabelsResponse = new EmailLabelsResponse();
				if (emailLabel[3] != null) {
					emailLabelsResponse.setLabelName((String) emailLabel[3]);
					emailLabelsResponse.setUserName((emailLabel[4] != null ? (String) emailLabel[4] : null));
					emailLabelsResponse.setUserName((emailLabel[6] != null ? (String) emailLabel[6] : null));
					emailLabelsResponse.setDate((emailLabel[7] != null ? (Timestamp) emailLabel[7] : null));
					emailLabelsResponses.add(emailLabelsResponse);
				}
			});
			mailMessage.setLabels(emailLabelsResponses);
			mailMessageList.add(mailMessage);
		}

	});
		LOGGER.info("getMailMessagesByEmailExtractionId: Added email message details to the response :{} ,uuid={}",mailMessageList,uuid);
		return mailMessageList;

}
	public List<MailMessageDTO> getMailMessagesProcessed(Pageable pageable,UUID uuid){
		List<MailMessageDTO> mailMessageList = new ArrayList<>();
		Map<Integer,String> referenceIdMap = new HashMap<>();
		Map<Integer,BigInteger> extractionIdCountMap = new HashMap<>();
		List<Object[]> mailMessgeQueryList = emailMessagesRepository.getAllMailMessagesProcessed(pageable);
		LOGGER.info("getMailMessagesProcessed: Retrieved processed email Messages raw list : {}, uuid={}",mailMessgeQueryList,uuid);
		List<Object[]> referenceIdmappingList = emailMessageExtractionRepository.getReferenceIds();
		LOGGER.info("getMailMessagesProcessed: Retrieved List of reference IDs : {} , uuid={}",referenceIdmappingList,uuid);
//		List<EmailAttachments>  emailAttachments = emailAttachmentsRepository.getAllEmailAttachments();
//		LOGGER.info("getMailMessagesProcessed: Retrieved all email attachments : {} , uuid={}",emailAttachments,uuid);
//
//		List<Integer> emailMessageIds = emailAttachments.stream().map(e->e.getEmailMessageId()).collect(Collectors.toList());
		List<Integer> emailMessageIds=emailAttachmentsRepository.getAllEmailMessageIds();
		List<Object[]> mappingCount =emailMessagesRepository.getExtractionMappingCount();
		LOGGER.info("getMailMessagesProcessed: Number of email messages which contains child messages by Extraction ID: {} , uuid={}",mappingCount,uuid);
		//check for multiple reference ids for same email message id in future
		LOGGER.info("getMailMessagesProcessed: Adding all processed email messages to the response: uuid={}",uuid);
		List<Integer> emailExtractionIdsList = getExtIdsList(mailMessgeQueryList,"processed");
		List<Integer> emailMessageIdsList = getEmailIdsList(mailMessgeQueryList,"processed");
		Map<Object[],Integer> emailLabelsList = getEmailLabels(emailExtractionIdsList);
		Map<Object[],Integer> emailLabelsByIdList = getEmailLabelsById(emailMessageIdsList);
		Map<UserLabelIfc,Integer> userLabelsList = getUserLabelsList(emailMessageIdsList);

		referenceIdmappingList.stream().forEach(ref->{
			referenceIdMap.put((Integer)ref[1], (String)ref[2]);
		});
		mappingCount.stream().forEach(ref-> extractionIdCountMap.put((Integer)ref[0], (BigInteger)ref[1]));

		mailMessgeQueryList.stream().forEach(mail->{
			MailMessageDTO mailMessage = new MailMessageDTO();
			mailMessage.setEmailMessageId((Integer) mail[0]);
			mailMessage.setSubject((String) mail[2]);
			mailMessage.setDateSent((Timestamp) mail[3]);
			mailMessage.setPartyName((String) mail[4]);
			mailMessage.setIsSeen((Boolean) mail[5]);
			if(mail[9]!=null){
				mailMessage.setRequestId((Integer) mail[9]);
			}
			if(mail[10]!=null) {
		         mailMessage.setEmailMessagesCount((BigInteger) mail[10]);
		    	}
			if(emailMessageIds.contains((Integer)mail[0])) {
				mailMessage.setAttachmentPresent(true);
			}
			else {
				mailMessage.setAttachmentPresent(false);
			}
			if(referenceIdMap.containsKey((Integer)mail[0])){
				mailMessage.setReferenceId(referenceIdMap.get((Integer)mail[0]));
			}
			if(mail[7] != null){
				Timestamp startTime= (Timestamp) mail[7];
				ZoneId gmtZone=ZoneId.of("GMT");
				ZonedDateTime gmtDateTime=ZonedDateTime.now(gmtZone);
				LocalDateTime currentTime=gmtDateTime.toLocalDateTime().withNano(0);
				Duration duration=Duration.between(currentTime, startTime.toLocalDateTime());
				long days=duration.toDays();
				long hours=duration.toHours()%24;
				long minutes=duration.toMinutes()%60;
				String Days=days+"d:"+hours+"h:"+minutes+"m";
				mailMessage.setDaysUntil(Days);
			}
			addLabelsProcessed(mail,mailMessage,emailLabelsList,emailLabelsByIdList,userLabelsList,"processed");
			mailMessageList.add(mailMessage);
		});
		LOGGER.info("getMailMessagesProcessed: Added all processed email messages to the response : {}, uuid={}",mailMessageList,uuid);

		return mailMessageList;
	}

	public void addLabelsProcessed(Object[] mail, MailMessageDTO mailMessage1,Map<Object[],Integer> emailLabelsByExtId,Map<Object[],Integer> emailLabelsByEmailId,Map<UserLabelIfc,Integer> userLabelIfcList,String type){
		List<EmailLabelsResponse> emailLabelsResponses1=new ArrayList<>();
		List<Object[]>  emailLabels1 = new ArrayList<>();
		Integer extractionId = Objects.equals(type, "processed") ?(Integer) mail[8]:(Integer) mail[0];
		Integer emailId = Objects.equals(type, "processed") ?(Integer) mail[0]:(Integer) mail[1];
		if(emailLabelsByExtId.containsValue(extractionId)) {
			emailLabels1 = emailLabelsByExtId.entrySet()
					.stream()
					.filter(e -> e.getValue().equals(extractionId))
					.map(Map.Entry::getKey)
					.collect(Collectors.toList());
		}
		else if(emailLabelsByEmailId.containsValue(emailId)){
			emailLabels1 = emailLabelsByEmailId.entrySet()
					.stream()
					.filter(e -> e.getValue().equals(emailId))
					.map(Map.Entry::getKey)
					.collect(Collectors.toList());
		}
		if(userLabelIfcList.containsValue(emailId)){
			List<UserLabelIfc> userLabels = userLabelIfcList.entrySet()
					.stream()
					.filter(e -> e.getValue().equals(emailId))
					.map(Map.Entry::getKey)
					.collect(Collectors.toList());
			mailMessage1.setUserLabels(userLabels);
		}
		if(!emailLabels1.isEmpty()) {
			addLabels(emailLabels1,emailLabelsResponses1);
		}
		mailMessage1.setLabels(emailLabelsResponses1);
	}

	public void addLabels(List<Object[]> emailLabels,List<EmailLabelsResponse> emailLabelsResponses){
		emailLabels.stream().
				forEach(emailLabel -> {
			EmailLabelsResponse emailLabelsResponse = new EmailLabelsResponse();
			emailLabelsResponse.setLabelName((String) emailLabel[1]);
			if (emailLabelsResponse.getLabelName().equalsIgnoreCase(Constants.IN_PROGRESS)) {
				emailLabelsResponse.setUserName(((String) emailLabel[2] != null ? (String) emailLabel[2] : null));
			}
			if (emailLabelsResponse.getLabelName().equalsIgnoreCase(Constants.MANUALLY_PROCESSED)) {
				emailLabelsResponse.setUserName(((String) emailLabel[3] != null ? (String) emailLabel[3] : null));
				emailLabelsResponse.setDate(((Timestamp) emailLabel[4] != null ? (Timestamp) emailLabel[4] : null));
			}
			emailLabelsResponses.add(emailLabelsResponse);
		});
	}
	
	public  Map<String,List<String>> getUtsValidatedNetworkElements(Integer emailMessageId, UUID uuid) {
		List<String> emailMessageNetworkElements  = new ArrayList<>();
		Integer emailMessageExtractionId=emailMessageExtractionRepository.getEmailMessageExtractionIdByEmailMessageId(emailMessageId);
		List<EmailMessageNetworkElements> emailMessageNetworkElementsList =emailMessageNetworkElementsRepository.findNetworkElementsByEmailMessageExtractionId(emailMessageExtractionId);
		if(!emailMessageNetworkElementsList.isEmpty() && emailMessageNetworkElementsList!=null) {
			emailMessageNetworkElementsList.stream().forEach(element->{
				emailMessageNetworkElements.add(element.getNetworkElementName());
			});
		}

	    StopWatch watch = new StopWatch();
	    watch.start();
		Map<String,List<String>> eqpTypes=equipmentValidationService.getEquipmentTypes(emailMessageNetworkElements, uuid);
		watch.stop();
	    LOGGER.info("Total time taken to get network Elements Response from uts : {}, uuid={}",
	    watch.getTotalTimeMillis(), uuid);
		return eqpTypes;	
	}

	public EmailResponseDTO findEmailMessageByEmailMessageId(Integer emailMessageId,Integer emailExtractionId,UUID uuid) {
		EmailResponseDTO emailResponseDTO= new EmailResponseDTO();
		List<EmailAttachmentsDTO> emailAttachmentsDTO = new ArrayList<>();
		List<EmailAttachments> emailAttachmentsforEmailMessageId;
		EmailMessageStatus emailMessageStatusForwarded=emailMessageStatusService.getEmailMessageStatusByName(Constants.EMAIL_MESSAGE_STATUS_FORWARDED);
		EmailMessageStatus emailMessageStatusReplied=emailMessageStatusService.getEmailMessageStatusByName(Constants.EMAIL_MESSAGE_STATUS_REPLIED);
		LOGGER.info("findEmailMessageByEmailMessageId: Retrieved message status for replied and forwarded : {} ,{}, uuid={}",emailMessageStatusReplied,emailMessageStatusForwarded,uuid);
		Integer emailMessageExtractionId=emailExtractionId!=null?emailExtractionId:emailMessageExtractionRepository.getEmailMessageExtractionIdByEmailMessageId(emailMessageId);
		LOGGER.info("findEmailMessageByEmailMessageId:Email message extraction ID was retrieved : {}, uuid={}",emailMessageExtractionId,uuid);
		if(emailMessageExtractionId != null) {
			emailMessageId = emailMessagesRepository.getParentEmailMessageIdByEmailMessageExtractionId(emailMessageExtractionId);
			LOGGER.info("findEmailMessageByEmailMessageId:Parent Email Message Id was retrieved : {}, uuid={}",emailMessageId,uuid);
		}
		List<ReferenceIFC> emailMessageExtractions = emailMessageExtractionRepository.getAllExtractionDetails(emailMessageId);
		emailResponseDTO.setReferenceIdDetails(!emailMessageExtractions.isEmpty()?emailMessageExtractions:null);
		EmailMessages emailMessages=emailMessagesRepository.getEmailMessageByEmailMessageId(emailMessageId);
		if(emailMessages.getEmailMessageId()!=null || !(emailMessages.getEmailMessageId().equals(0))) {
			emailResponseDTO.setEmailLockResponse(updateEmailResponseWithLockInfo(emailMessages));
			String messageStatusName = updateMessageStatusWithNoActionRequired( emailMessages);
			emailResponseDTO.setMessageStatusName(messageStatusName);
		}
 
		LOGGER.info("findEmailMessageByEmailMessageId:Email Message details {} for the Email Message Id {} : {}, uuid={}",emailMessages,emailMessageId,uuid);
		emailResponseDTO.setLanguage(emailMessages.getLanguage());
		Messages message =messagesRepository.getMessageByMessageId(emailMessages.getMessageId());
		LOGGER.info("findEmailMessageByEmailMessageId:Message details {} for the Message Id {} : {}, uuid={}",message,emailMessages.getMessageId(),uuid);
		String referenceId=emailMessageExtractionRepository.getReferenceIdByEmailMessageId(emailMessageExtractionId);
		LOGGER.info("findEmailMessageByEmailMessageId: ReferenceId  : {}, uuid={}",referenceId,uuid);
		//check for multiple extraction records  for same email message in future
		EmailMessageExtraction emailMessageExtraction=emailMessageExtractionRepository.findExtractionRecordByEmailMessageExtractionId(emailMessageExtractionId);
		LOGGER.info("findEmailMessageByEmailMessageId: Email Message Extraction Record  : {}, uuid={}",emailMessageExtraction,uuid);
		ExtractionConfidence extractionConfidence =extractionConfidenceRepository.getExtractionConfidenceByEmailExtractionId(emailMessageExtractionId);
		LOGGER.info("findEmailMessageByEmailMessageId: Extraction Confidence  : {}, uuid={}",extractionConfidence,uuid);
		List<EmailMessageNetworkElements> emailMessageNetworkElementsList =emailMessageNetworkElementsRepository.findNetworkElementsByEmailMessageExtractionId1(emailMessageExtractionId);
		LOGGER.info("findEmailMessageByEmailMessageId: Network Element List {} for the email Message id  : {}, uuid={}",emailMessageNetworkElementsList,emailMessageId,uuid);
		  emailAttachmentsforEmailMessageId=emailAttachmentsRepository.getEmailAttachmentsByEmailMessageId(emailMessageId);
		LOGGER.info("findEmailMessageByEmailMessageId: Email Attachments {} for the email Message id  : {}, uuid={}",emailAttachmentsforEmailMessageId,emailMessageId,uuid);

        LOGGER.info("findEmailMessageByEmailMessageId: Adding email Message data into the response , uuid={}",uuid);

        emailResponseDTO.setExtractionConfidence(extractionConfidence);
          if(!emailAttachmentsforEmailMessageId.isEmpty() && emailAttachmentsforEmailMessageId!=null) {
          emailAttachmentsforEmailMessageId.stream().forEach(attachment->{
        	  EmailAttachmentsDTO emailAttachmentsDTOIterate = new EmailAttachmentsDTO();
      		String fileContent = new String(attachment.getAttachmentFile(), StandardCharsets.UTF_8);
  			emailAttachmentsDTOIterate.setEmailAttachments(attachment);
  			emailAttachmentsDTOIterate.setFileContent(fileContent);
  			emailAttachmentsDTO.add(emailAttachmentsDTOIterate);
          }); 
          };
		emailResponseDTO.setEmailAttachmentsList(emailAttachmentsDTO);
		LOGGER.info("findEmailMessageByEmailMessageId: Attachments were added to the email response ,{}, uuid={}",emailResponseDTO,uuid);
		if(emailMessages.getPartyId()!=null) {
			Party party = partyRepository.getPartyByKey(emailMessages.getPartyId());
			emailResponseDTO.setPartyName(party.getPartyName());
		}
		Map<String,Object> validNetworkElementsWithConfidence=new HashMap<>();
		Map<String,Object> inValidNetworkElementsWithConfidence=new HashMap<>();
		if(!emailMessageNetworkElementsList.isEmpty() && emailMessageNetworkElementsList!=null) {
			emailMessageNetworkElementsList
					.stream()
					.filter(e ->e.getValid())
					.forEach(e-> validNetworkElementsWithConfidence
							.put(e.getNetworkElementName(), e.getNetworkElementConfidence()));
			emailMessageNetworkElementsList.stream().filter(e ->!e.getValid())
					.forEach(e-> inValidNetworkElementsWithConfidence.put(e.getNetworkElementName(), e.getNetworkElementConfidence()));
		}
		LOGGER.info("findEmailMessageByEmailMessageId: Network Elements were divided into valid and invalid network elements ,emailMessageNetworkElementsList={}, uuid={}",emailMessageNetworkElementsList,uuid);

		emailResponseDTO.setReferenceId(referenceId);
		emailResponseDTO.setSubject(emailMessages.getSubject());

		if (emailMessages.getEmailMessageStatusId() != null && emailMessages.getEmailMessageStatusId().equals(emailMessageStatusForwarded.getEmailMessageStatusId())) {
			emailResponseDTO.setDirection(emailMessageStatusForwarded.getEmailMessageStatusName());
		} else if (emailMessages.getEmailMessageStatusId()!= null && emailMessages.getEmailMessageStatusId().equals(emailMessageStatusReplied.getEmailMessageStatusId())) {
			emailResponseDTO.setDirection(emailMessageStatusReplied.getEmailMessageStatusName());
		} else {
			emailResponseDTO.setDirection(message.getDirection());
		}
		emailResponseDTO.setSender(message.getSender());
		List<String> emailRecipients=messageRecipientRepository.getEmailDomainByMessageId(message.getMessagesId());
		if(message.getRecipient() != null && !message.getRecipient().isEmpty() ){
			emailResponseDTO.setRecipient(emailRecipients);
		}
		else {
			emailResponseDTO.setRecipient(Collections.singletonList(message.getRecipient()));
		}
		//emailResponseDTO.setRecipient(message.getRecipient());
		emailResponseDTO.setEmailMessageId(emailMessageId);
		emailResponseDTO.setUserLabels(emailMessagesRepository.getUserLabels(emailMessageId));
		emailResponseDTO.setDateReceived(message.getDateReceived());
		if(emailMessageExtraction!=null) {
		emailResponseDTO.setStartDate(emailMessageExtraction.getStartDate());
		emailResponseDTO.setEndDate(emailMessageExtraction.getEndDate());
		emailResponseDTO.setOutageNumber(emailMessageExtraction.getOutageNumber());
		emailResponseDTO.setOutageDuration(emailMessageExtraction.getOutageDuration());
		emailResponseDTO.setOutageDurationUom(emailMessageExtraction.getOutageDurationUom());
		emailResponseDTO.setCity(emailMessageExtraction.getCity());
		emailResponseDTO.setState(emailMessageExtraction.getState());
		emailResponseDTO.setCountry(emailMessageExtraction.getCountry());
		emailResponseDTO.setNumberOfOutages(emailMessageExtraction.getOutageNumber());
		emailResponseDTO.setDescription(emailMessageExtraction.getDescription());
		}
		emailResponseDTO.setEmailMessageExtractionId(emailMessageExtractionId);

		emailResponseDTO.setNetworkElements(emailMessageNetworkElementsRepository.findNetworkElementsByEmailMessageExtractionId2(emailMessageExtractionId));

		if(emailMessages.getLanguage()!=null && emailMessages.getLanguage().equalsIgnoreCase("en")) {
			emailResponseDTO.setBodyText(emailMessages.getBodyText());
		}
		else {
			emailResponseDTO.setBodyText(emailMessages.getBodyTranslated());
		}
		emailResponseDTO.setBodyHtml(emailMessages.getBodyHtml());
		Map<String,String> modifiedBy=new HashMap<>();
		List<EmailMessageExtractionAuditLog> emailMessageExtractionAuditLogs=emailMessageExtractionAuditLogRepository.getEmailMessageExtractionAuditLogsByEmailMessageExtractionId(emailMessageExtractionId);
		for(EmailMessageExtractionAuditLog emailMessageExtractionAuditLog:emailMessageExtractionAuditLogs) {
			switch (emailMessageExtractionAuditLog.getItemChanged()) {
				case "City":
					emailResponseDTO.setCity(emailMessageExtractionAuditLog.getNewValue());
					modifiedBy.put("cityModifiedBy", (emailMessageExtractionAuditLog.getModifiedBy() + " " + emailMessageExtractionAuditLog.getModifiedDate()));
					break;
				case "State":
					emailResponseDTO.setState(emailMessageExtractionAuditLog.getNewValue());
					modifiedBy.put("stateModifiedBy", (emailMessageExtractionAuditLog.getModifiedBy() + " " + emailMessageExtractionAuditLog.getModifiedDate()));
					break;
				case "Country":
					emailResponseDTO.setCountry(emailMessageExtractionAuditLog.getNewValue());
					modifiedBy.put("countryModifiedBy", (emailMessageExtractionAuditLog.getModifiedBy() + " " + emailMessageExtractionAuditLog.getModifiedDate()));
					break;
				case "Start Date":
					DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss");
					emailResponseDTO.setStartDate(emailMessageExtraction.getStartDate());
					modifiedBy.put("startDateModifiedBy", (emailMessageExtractionAuditLog.getModifiedBy() + " " + emailMessageExtractionAuditLog.getModifiedDate()));
					break;
				case "End Date":
					DateTimeFormatter formatter1 = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss");
					emailResponseDTO.setEndDate(emailMessageExtraction.getEndDate());
					modifiedBy.put("EndDateModifiedBy", (emailMessageExtractionAuditLog.getModifiedBy() + " " + emailMessageExtractionAuditLog.getModifiedDate()));
					break;
				case "Outage Duration":
					emailResponseDTO.setOutageDuration(Integer.parseInt(emailMessageExtractionAuditLog.getNewValue()));
					modifiedBy.put("outageDurationModifiedBy", (emailMessageExtractionAuditLog.getModifiedBy() + " " + emailMessageExtractionAuditLog.getModifiedDate()));
					break;
				case "Outage UOM":
					emailResponseDTO.setOutageDurationUom(emailMessageExtractionAuditLog.getNewValue());
					modifiedBy.put("outageUOMModifiedBy", (emailMessageExtractionAuditLog.getModifiedBy() + " " + emailMessageExtractionAuditLog.getModifiedDate()));
					break;
				case "Description":
					emailResponseDTO.setDescription(emailMessageExtractionAuditLog.getNewValue());
					modifiedBy.put("descriptionModifiedBy", (emailMessageExtractionAuditLog.getModifiedBy() + " " + emailMessageExtractionAuditLog.getModifiedDate()));
					break;
			}
		}
        LOGGER.info("findEmailMessageByEmailMessageId: Email Details with modified change plan details were Added to the response  : {}, uuid={}",emailResponseDTO,uuid);

        List<EmailMessageExtractionAuditLog> emailMessageExtractionAuditLogNetworkElements=emailMessageExtractionAuditLogRepository.findNetworkElementsByEmailMessageExtractionId1(emailMessageExtractionId);
			if(emailMessageExtractionAuditLogNetworkElements != null && !emailMessageExtractionAuditLogNetworkElements.isEmpty()) {
				  emailMessageExtractionAuditLogNetworkElements
						  .stream()
						  .filter(i -> i.getItemChanged().equalsIgnoreCase("Valid Network Element"))
						  .forEach(x-> validNetworkElementsWithConfidence
								  .put(x.getNewValue(), (x.getModifiedBy()+" "+x.getModifiedDate())));
				 emailMessageExtractionAuditLogNetworkElements
						 .stream().
						 filter(i ->  i.getItemChanged().equalsIgnoreCase("Invalid Network Element")).
						 forEach(i-> inValidNetworkElementsWithConfidence
								 .put(i.getNewValue(),  (i.getModifiedBy()+" "+i.getModifiedDate())));
			}
			emailResponseDTO.setValidEmailMessageNetworkElementsListWithConfidence(validNetworkElementsWithConfidence);
			emailResponseDTO.setInValidEmailMessageNetworkElementsListWithConfidence(inValidNetworkElementsWithConfidence);
			emailResponseDTO.setModifiedBy(modifiedBy);
        LOGGER.info("findEmailMessageByEmailMessageId: Network Elements were Added to the response  : {}, uuid={}",emailResponseDTO,uuid);

        emailResponseDTO.setParentRecipient(message.getRecipient());
			emailResponseDTO.setParentSender(message.getSender());
			//Getting all the releated Email messages for the email Message ID;
		List<Object[]> conversations = new ArrayList<Object[]>();
		List<EmailMessagesDTO> emailMessagesDTOList = new ArrayList<EmailMessagesDTO>();
		if(emailMessageExtractionId != null){
			conversations=emailMessagesRepository.getEmailMessagesByEmailMessageExtractionId(emailMessageExtractionId);
		}
		if(!conversations.isEmpty() && conversations != null){
			Integer finalEmailMessageId = emailMessageId;
			conversations.stream().forEach(conversation->{
				EmailMessagesDTO emailMessageDTO = new EmailMessagesDTO();
				emailMessageDTO.setEmailMessageId((Integer) conversation[3]);
				Integer status;
				if(finalEmailMessageId != emailMessageDTO.getEmailMessageId()) {
					emailMessageDTO.setSender((String) conversation[0]);
					List<String> emailRecipients1=new ArrayList<String>();
					emailRecipients1=messageRecipientRepository.getEmailDomainByMessageId((Integer) conversation[8]);
					if(emailRecipients1 != null && !emailRecipients1.isEmpty()){
						emailMessageDTO.setRecipient( emailRecipients1);
					}
					else {
						List<String> recipient=new ArrayList<>();
						recipient.add((String) conversation[1]);
						emailMessageDTO.setRecipient(recipient);
					}
					Timestamp timestamp = (Timestamp) conversation[2];
					emailMessageDTO.setDateReceived(timestamp.toLocalDateTime());
					emailMessageDTO.setSubject((String) conversation[4]);
					emailMessageDTO.setBodyText((String) conversation[5]);
					emailMessageDTO.setBodyHtml((String) conversation[6]);
					status = (Integer) conversation[7];
					if (status != null && status.equals(emailMessageStatusForwarded.getEmailMessageStatusId())) {
						emailMessageDTO.setDirection(emailMessageStatusForwarded.getEmailMessageStatusName());
					} else if (status != null && status.equals(emailMessageStatusReplied.getEmailMessageStatusId())) {
						emailMessageDTO.setDirection(emailMessageStatusReplied.getEmailMessageStatusName());
					} else {
						emailMessageDTO.setDirection("inbound");
					}
					List<EmailAttachmentsDTO> emailAttachmentsChildDTO = new ArrayList<>();
					List<EmailAttachments> emailAttachmentsByEmailMessageId = emailAttachmentsRepository.getEmailAttachmentsByEmailMessageId(emailMessageDTO.getEmailMessageId());
					if (!emailAttachmentsByEmailMessageId.isEmpty() && emailAttachmentsByEmailMessageId != null) {
						emailAttachmentsByEmailMessageId.stream().forEach(attachment -> {
							EmailAttachmentsDTO emailAttachmentsDTOIterate = new EmailAttachmentsDTO();
							String fileContent = new String(attachment.getAttachmentFile(), StandardCharsets.UTF_8);
							emailAttachmentsDTOIterate.setEmailAttachments(attachment);
							emailAttachmentsDTOIterate.setFileContent(fileContent);
							emailAttachmentsChildDTO.add(emailAttachmentsDTOIterate);
						});
					}
					;
					emailMessageDTO.setEmailAttachmentsList(emailAttachmentsChildDTO);
					emailMessagesDTOList.add(emailMessageDTO);
				}});
				emailResponseDTO.setConversations(emailMessagesDTOList);
            LOGGER.info("findEmailMessageByEmailMessageId: Total Email Conversations were Added to the response  : {}, uuid={}",emailResponseDTO,uuid);

        }
		addLabelsViewPage(emailResponseDTO,emailMessageExtractionId);
		setEmailRequestIds(emailResponseDTO, emailMessageExtractionId, validNetworkElementsWithConfidence,uuid);

		return emailResponseDTO;
	}

	private void addLabelsViewPage(EmailResponseDTO emailResponseDTO,Integer emailMessageExtractionId) {
		Set<String> labels=new HashSet<>();
		labels=emailMessageLabelsRepository.getMessageLabelsByemailMessageId(emailResponseDTO.getEmailMessageId());
		emailResponseDTO.setLabels(labels);
	}

	private EmailLockResponse updateEmailResponseWithLockInfo(EmailMessages emailMessages) {
		EmailLockResponse emailLockResponse = null;
		if (emailMessages != null && emailMessages.getLockedBy() !=null) {
			emailLockResponse = new EmailLockResponse();
			emailLockResponse.setEmailMessageId(emailMessages.getEmailMessageId());
			emailLockResponse.setLocked(emailMessages.getIsLocked());
			emailLockResponse.setLockedAt(emailMessages.getLockedAt());
			emailLockResponse.setLockedBy(emailMessages.getLockedBy());
		}
		return emailLockResponse;
	}

	private void setEmailRequestIds(EmailResponseDTO emailResponseDTO, Integer emailMessageExtractionId, Map<String, Object> validNetworkElementsWithConfidence,UUID uuid){
		try {
			List<EmailMessageTPMRequest> emailMessageTPMRequestList = emailMessageTPMRequestRepository.
					getAllByEmailMessageExtractionId(emailMessageExtractionId);
			LOGGER.info("MailHandlingService# getAllByEmailMessageExtractionId#:Email message Tpm Request List : {}, uuid={}", emailMessageTPMRequestList, uuid);
			List<EmailRequestsDTO> emailRequestsDTOList = new ArrayList<>();
			for (EmailMessageTPMRequest e : emailMessageTPMRequestList) {
				EmailRequestsDTO emailRequestsDTO = new EmailRequestsDTO();
				emailRequestsDTO.setRequestId(e.getRequestId());
				emailRequestsDTO.setStartDate(e.getStartDate());
				emailRequestsDTO.setEndDate(e.getEndDate());
				emailRequestsDTO.setUsername(e.getSubmittedBy());
				emailRequestsDTO.setSubmittedAt(e.getSubmittedDate());
				List<String> validNetworkElements = new ArrayList<>();
				List<String> invalidNetworkElements = new ArrayList<>();
				if (e.getRequestId() != null) {
					List<TPMRequestNetworkElements> networkElementList = tPMRequestNetworkElementsRepository.getAllByRequestId(e.getRequestId());
					LOGGER.info("MailHandlingService# getAllByRequestId#:Tpm Request Network Elements List : {}, uuid={}", networkElementList, uuid);
					List<NetworkElementDTO> networkElementDTOList = new ArrayList<>();
					for (TPMRequestNetworkElements networkElement : networkElementList) {
						if (validNetworkElementsWithConfidence.containsKey(networkElement.getNetworkElementName())) {
							validNetworkElements.add(networkElement.getNetworkElementName());
						} else {
							invalidNetworkElements.add(networkElement.getNetworkElementName());
						}
					}
				}
				emailRequestsDTO.setFoundInInventory(validNetworkElements);
				emailRequestsDTO.setNotFoundInInventory(invalidNetworkElements);
				emailRequestsDTOList.add(emailRequestsDTO);
			}
			emailResponseDTO.setRequestId(emailRequestsDTOList);
		}catch(Exception ex){
			LOGGER.info("set Email request Id failed: Error While sending Message: {}, uuid={}",uuid);

		}
	}


	public ResponseEntity<ModelApiResponse> updateEmailMessageStatus(Integer emailMessageId,Boolean status,UUID uuid) {
		ModelApiResponse modelApiResponse = new ModelApiResponse();
		try{
		EmailMessages mailToUpdate=emailMessagesRepository.findById(emailMessageId).get();
		mailToUpdate.setSeen(status);
		emailMessagesRepository.save(mailToUpdate);
		if(status==true){
			LOGGER.info("updateEmailMessageStatus: Email message status of email Message Id {} was updated, uuid={}",mailToUpdate.getEmailMessageId(),uuid);
			modelApiResponse.setMessage("Marked as Read");
		}
		else{
			LOGGER.info("updateEmailMessageStatus: Email message status of email Message Id {} was updated, uuid={}",mailToUpdate.getEmailMessageId(),uuid);
		modelApiResponse.setMessage("Marked as UnRead");}
		modelApiResponse.setCode(200);
		return new ResponseEntity<>(modelApiResponse, HttpStatus.OK);
		}
		catch (NoSuchElementException e){
			LOGGER.info("updateEmailMessageStatus: Record with email Message Id {} was not found : uuid={}",emailMessageId,uuid);
			modelApiResponse.message("record with id '"+ emailMessageId +"' wasn't found");
			modelApiResponse.code(400);
			return new ResponseEntity<>(modelApiResponse, HttpStatus.NOT_FOUND);
		}

	}
	public List<MailMessageDTO> processMailMessage(List<Object[]> mailMessgeQueryList,UUID uuid){
		List<MailMessageDTO> mailMessageList = new ArrayList<>();
		Map<Integer,String> referenceIdMap = new HashMap<>();
		List<Object[]> referenceIdmappingList = emailMessageExtractionRepository.getReferenceIds();
		LOGGER.info("processMailMessage: processing email messages : uuid={}",uuid);
//		List<EmailAttachments> emailAttachments = emailAttachmentsRepository.getAllEmailAttachments();
//		List<Integer> emailMessageIds = emailAttachments.stream().map(e->e.getEmailMessageId()).collect(Collectors.toList());
		//check for multiple reference ids for same email message id in future
		List<Integer> emailMessageIds=emailAttachmentsRepository.getAllEmailMessageIds();
		referenceIdmappingList.stream().forEach(ref->{
			referenceIdMap.put((Integer)ref[1], (String)ref[2]);
		});
		mailMessgeQueryList.stream().forEach(mail->{
			MailMessageDTO mailMessage = new MailMessageDTO();
			mailMessage.setEmailMessageId((Integer) mail[0]);
			mailMessage.setSubject((String) mail[2]);
			mailMessage.setDateSent((Timestamp) mail[3]);
			mailMessage.setPartyName((String) mail[4]);
			mailMessage.setIsSeen((Boolean) mail[5]);
			if(emailMessageIds.contains((Integer)mail[0])) {
				mailMessage.setAttachmentPresent(true);
			}
			else {
				mailMessage.setAttachmentPresent(false);
			}
			if(referenceIdMap.containsKey((Integer)mail[0])){
				mailMessage.setReferenceId(referenceIdMap.get((Integer)mail[0]));
			}
			mailMessageList.add(mailMessage);
		});
		LOGGER.info("processMailMessage: processed email messages :{}, uuid={}",mailMessageList,uuid);

		return mailMessageList;
	}
	public Map<String,Integer> getEmailMessageListCount(String userName,UUID uuid){
		Map<String,Integer> map=new HashMap<>();
        ZoneId gmtZone=ZoneId.of("GMT");
        ZonedDateTime gmtDateTime=ZonedDateTime.now(gmtZone);
		LocalDateTime currentTime=gmtDateTime.toLocalDateTime().withNano(0);
		LocalDateTime pastTime=currentTime.minus(24, ChronoUnit.HOURS);
		List<Object[]> mailMessgeQueryList = emailMessagesRepository.getAllNewMailMessagesInTimeRange(pastTime,currentTime);
		map.put("newEmails",mailMessgeQueryList.size());
		LOGGER.info("getEmailMessageListCount: size of new emails received in last 24 hours :{}, uuid={}",mailMessgeQueryList.size(),uuid);
		mailMessgeQueryList = emailMessagesRepository.getAllUnprocessedMessages();
		map.put("unProcessedAll",mailMessgeQueryList.size());
		LOGGER.info("getEmailMessageListCount: size of unprocessed emails :{}, uuid={}",mailMessgeQueryList.size(),uuid);
		mailMessgeQueryList = emailMessagesRepository.getAllUnprocessedandUnreadMessages();
		map.put("unRead",mailMessgeQueryList.size());
		LOGGER.info("getEmailMessageListCount: size of unprocessed unread emails :{}, uuid={}",mailMessgeQueryList.size(),uuid);
		//inProgress->edited by me and unprocessed status
		mailMessgeQueryList = emailMessagesRepository.getInprogressMailMessagesManuallyProcessedByMe(userName);
		map.put("inProgress",mailMessgeQueryList.size());
		LOGGER.info("getEmailMessageListCount: size of  inProgress emails :{}, uuid={}",mailMessgeQueryList.size(),uuid);
		pastTime=currentTime.minus(168,ChronoUnit.HOURS);
		mailMessgeQueryList = emailMessagesRepository.getMailMessagesManuallyProcessedByMe(userName,currentTime,pastTime);
		map.put("manuallyProcessedByMe",mailMessgeQueryList.size());
		LOGGER.info("getEmailMessageListCount: size of  manually processed by {} emails :{}, uuid={}",userName,mailMessgeQueryList.size(),uuid);
		LocalDateTime endTime=currentTime.plus(6,ChronoUnit.HOURS);
		mailMessgeQueryList = emailMessagesRepository.getUnprocessedMessagesInTimeRange(currentTime,endTime);
		map.put("unProcessed6Hours",mailMessgeQueryList.size());
		LOGGER.info("getEmailMessageListCount: size of  unprocessed emails scheduled in next 6 hours:{}, uuid={}",mailMessgeQueryList.size(),uuid);
		endTime=currentTime.plus(12,ChronoUnit.HOURS);
		mailMessgeQueryList = emailMessagesRepository.getUnprocessedMessagesInTimeRange(currentTime,endTime);
		map.put("unProcessed12Hours",mailMessgeQueryList.size());
		LOGGER.info("getEmailMessageListCount: size of  unprocessed emails scheduled in next 12 hours:{}, uuid={}",mailMessgeQueryList.size(),uuid);
		endTime=currentTime.plus(24,ChronoUnit.HOURS);
		mailMessgeQueryList = emailMessagesRepository.getUnprocessedMessagesInTimeRange(currentTime,endTime);
		map.put("unProcessed24Hours",mailMessgeQueryList.size());
		LOGGER.info("getEmailMessageListCount: size of  unprocessed emails scheduled in next 24 hours:{}, uuid={}",mailMessgeQueryList.size(),uuid);
		endTime=currentTime;
		LocalDateTime startTime=currentTime.minus(24, ChronoUnit.HOURS);
		mailMessgeQueryList = emailMessagesRepository.getAutoProcessedMailMessagesInTimeRange(startTime,endTime);
		map.put("autoProcessed",mailMessgeQueryList.size());
		LOGGER.info("getEmailMessageListCount: size of autoProcessed in last 24 hours:{}, uuid={}",mailMessgeQueryList.size(),uuid);
		mailMessgeQueryList = emailMessagesRepository.getManualProcessedMailMessagesInTimeRange(startTime,endTime);
		map.put("manualProcessed",mailMessgeQueryList.size());
		return map;
	}
	public List<MailMessageDTO> getMailMessagesByType(String type,int hours,String userName,UUID uuid){
		List<MailMessageDTO> mailMessageList = new ArrayList<>();
		ZoneId gmtZone=ZoneId.of("GMT");
		ZonedDateTime gmtDateTime=ZonedDateTime.now(gmtZone);
		LocalDateTime currentTime=gmtDateTime.toLocalDateTime().withNano(0);
		if(type.equalsIgnoreCase("newemails")){
			LocalDateTime pastTime=currentTime.minus(24, ChronoUnit.HOURS);
			List<Object[]> mailMessgeQueryList = emailMessagesRepository.getAllNewMailMessagesInTimeRange(pastTime,currentTime);
			mailMessageList=this.processMailMessage(mailMessgeQueryList,uuid);
			LOGGER.info("getEmailMessageListCount: List of new emails received in last 24 hours :{}, uuid={}",mailMessgeQueryList,uuid);

		}
		else if(type.equalsIgnoreCase("unprocessed")){
			LocalDateTime endTime=currentTime.plus(hours,ChronoUnit.HOURS);
			List<Object[]> mailMessgeQueryList = emailMessagesRepository.getUnprocessedMessagesInTimeRange(currentTime,endTime);
			mailMessageList=this.processMailMessage(mailMessgeQueryList,uuid);
			LOGGER.info("getEmailMessageListCount: size of  unprocessed emails scheduled in next {} hours:{}, uuid={}",hours,mailMessgeQueryList,uuid);

		}
		else if(type.equalsIgnoreCase("inProgress")){
			List<Object[]>  mailMessgeQueryList = emailMessagesRepository.getInprogressMailMessagesManuallyProcessedByMe(userName);
			mailMessageList=this.processMailMessage(mailMessgeQueryList,uuid);
			LOGGER.info("getEmailMessageListCount: List of  inProgress emails :{}, uuid={}",mailMessgeQueryList,uuid);
		}
		else if(type.equalsIgnoreCase("unprocessedAll")) {
			List<Object[]> mailMessgeQueryList = emailMessagesRepository.getAllUnprocessedMessages();
			mailMessageList=this.processMailMessage(mailMessgeQueryList,uuid);
			LOGGER.info("getEmailMessageListCount: List of unprocessed emails :{}, uuid={}",mailMessgeQueryList,uuid);
		}
		else if(type.equalsIgnoreCase("unread")){
			List<Object[]> mailMessgeQueryList = emailMessagesRepository.getAllUnprocessedandUnreadMessages();
			mailMessageList=this.processMailMessage(mailMessgeQueryList,uuid);
			LOGGER.info("getEmailMessageListCount: size of unprocessed unread emails :{}, uuid={}",mailMessgeQueryList,uuid);
		}
		else if(type.equalsIgnoreCase("autoprocessed")){
			LocalDateTime endTime=currentTime;
			LocalDateTime startTime=currentTime.minus(hours, ChronoUnit.HOURS);
			List<Object[]> mailMessgeQueryList = emailMessagesRepository.getAutoProcessedMailMessagesInTimeRange(startTime,endTime);
			mailMessageList=this.processMailMessage(mailMessgeQueryList,uuid);
			LOGGER.info("getEmailMessageListCount: size of autoProcessed in last {} hours:{}, uuid={}",mailMessgeQueryList,uuid);

		}
		else if(type.equalsIgnoreCase("manualProcessed")){
			LocalDateTime endTime=currentTime;
			LocalDateTime startTime=currentTime.minus(hours, ChronoUnit.HOURS);
			List<Object[]> mailMessgeQueryList = emailMessagesRepository.getManualProcessedMailMessagesInTimeRange(startTime,endTime);
			mailMessageList=this.processMailMessage(mailMessgeQueryList,uuid);
		}
		else if(type.equalsIgnoreCase("manuallyProcessedByMe")){
			LocalDateTime pastTime=currentTime.minus(168,ChronoUnit.HOURS);
			List<Object[]> mailMessgeQueryList = emailMessagesRepository.getMailMessagesManuallyProcessedByMe(userName,currentTime,pastTime);
			mailMessageList=this.processMailMessage(mailMessgeQueryList,uuid);
			LOGGER.info("getEmailMessageListCount: List of  manually processed by {} emails :{}, uuid={}",userName,mailMessgeQueryList,uuid);
		}
		else if(type.equalsIgnoreCase("backlog")){
			LocalDateTime endTime=LocalDateTime.now();
			LocalDateTime startTime=endTime.minus(hours,ChronoUnit.HOURS);
			List<Object[]> mailMessgeQueryList = emailMessagesRepository.getUnprocessedBacklogMessagesInTimeRange(startTime,endTime);
			mailMessageList=this.processMailMessage(mailMessgeQueryList,uuid);
			LOGGER.info("getEmailMessageListCount: List of backlog unprocessed emails :{}, uuid={}",mailMessgeQueryList,uuid);
		}
		return mailMessageList;
	}
	public void logSentEmail(Messages m,EmailNotificationsDTO emailNotificationsDTO,UUID uuid){
		//new Message and email_message creation
		//message new save
		MessageStatus correspondingEmailStatus = messageStatusService.getMessageStatusByName(Constants.MESSAGE_STATUS_SENT);
		//EMAIL MESSAGE STATUS <>
		EmailMessageStatus emailMessageStatus=new EmailMessageStatus();
		if(emailNotificationsDTO.getAction().equalsIgnoreCase("reply")){
			emailMessageStatus=emailMessageStatusService.getEmailMessageStatusByName(Constants.EMAIL_MESSAGE_STATUS_REPLIED);
		} else if (emailNotificationsDTO.getAction().equalsIgnoreCase("forward")) {
			emailMessageStatus=emailMessageStatusService.getEmailMessageStatusByName(Constants.EMAIL_MESSAGE_STATUS_FORWARDED);
		}
		m.setMessagesStatusId(correspondingEmailStatus.getMessageStatusId());
		m.setModifiedDate(LocalDateTime.now());
		m.setModifiedBy(Constants.CURRENT_MICROSERVICE);
		Messages messages=messagesRepository.save(m);
		LOGGER.info("logSentEmail: Message updated in the Messages table: {}, uuid={}",messages,uuid);
		MessageProcessingHistory messageProcessingHistory=new MessageProcessingHistory();
		messageProcessingHistory.setMessageId(m.getMessagesId());
		messageProcessingHistory.setCreatedDate(emailNotificationsDTO.getDateSent());
		messageProcessingHistory.setCreatedBy(emailNotificationsDTO.getCreatedBy());
		messageProcessingHistory.setMessageStatusId(correspondingEmailStatus.getMessageStatusId());
		messageProcessingHistoryRepository.save(messageProcessingHistory);
		LOGGER.info("logSentEmail: New record added in to the MessageProcessingHistory Table: {}, uuid={}",uuid);
		//email message new save
		EmailMessages e=emailMessagesRepository.getEmailMessageByMessageId(m.getMessagesId());
		e.setEmailMessageStatusId(emailMessageStatus.getEmailMessageStatusId());
		e.setModifiedDate(LocalDateTime.now());
		e.setModifiedBy(Constants.CURRENT_MICROSERVICE);
		emailMessagesRepository.save(e);
		LOGGER.info("logSentEmail: Email Message updated in the Email Messages table: {}, uuid={}",uuid);
		EmailMessageProcessingHistory emailMessageProcessingHistory2 =new EmailMessageProcessingHistory();
		emailMessageProcessingHistory2.setEmailMessageId(e.getEmailMessageId());
		emailMessageProcessingHistory2.setEmailMessageStatusId(emailMessageStatus.getEmailMessageStatusId());
		emailMessageProcessingHistory2.setCreatedBy(e.getCreatedBy());
		emailMessageProcessingHistory2.setCreatedDate(e.getCreatedDate());
		emailMessageProcessingHistoryRepository.save(emailMessageProcessingHistory2);


	}

	public Messages logEmail(EmailNotificationsDTO emailNotificationsDTO, UUID uuid){
		//------need to implement message status in email message status table.------
		MessageStatus composedStatus = messageStatusService.getMessageStatusByName(Constants.MESSAGE_STATUS_COMPOSED);
		EmailMessageStatus createdStatus = emailMessageStatusService.getEmailMessageStatusByName(Constants.EMAIL_MESSAGE_STATUS_CREATED);
		Integer emailMessageExtractionId=emailMessageExtractionRepository.getEmailMessageExtractionIdByEmailMessageId(emailNotificationsDTO.getEmailMessageId());
		Integer parentEmailMessageId = emailMessageExtractionService.getParentEmailMessageId(emailMessageExtractionId);

		//EMAIL TYPE <EMAIL>
		MessageTypes correspondingMessageType = messageTypesService.getMessageTypeByName(Constants.MESSAGE_TYPE_EMAIL);
		//EMAIL STATUS <>

		//Reply email addition into the Messages Table
		Messages message=new Messages();
		message.setMessagesTypeId(correspondingMessageType.getMessageTypeId());
		message.setMessagesStatusId(composedStatus.getMessageStatusId());
		message.setDirection("outbound");
		message.setDateSent(emailNotificationsDTO.getDateSent());
		message.setDateReceived(emailNotificationsDTO.getDateSent());
		message.setSender(emailNotificationsDTO.getSenderEmail());
		message.setCreatedBy(emailNotificationsDTO.getCreatedBy());
		message.setCreatedDate(emailNotificationsDTO.getDateSent());
		Messages m=messagesRepository.save(message);
		LOGGER.info("logEmail: new message record added to the Database: {}, uuid={}",m,uuid);
		for(String recipient:emailNotificationsDTO.getRecipients()) {
			MessageRecipient messageRecipient = new MessageRecipient();
			messageRecipient.setMessagesId(m.getMessagesId());
			messageRecipient.setEmailDomain(recipient);
			MessageRecipient mRecipient=messageRecipientRepository.save(messageRecipient);
			LOGGER.info("logEmail: MessageRecipient Created in the Database: {}, uuid={}",mRecipient,uuid);
		}
		

		MessageProcessingHistory messageProcessingHistory=new MessageProcessingHistory();
		messageProcessingHistory.setMessageId(m.getMessagesId());
		messageProcessingHistory.setCreatedDate(emailNotificationsDTO.getDateSent());
		messageProcessingHistory.setCreatedBy(emailNotificationsDTO.getCreatedBy());
		messageProcessingHistory.setMessageStatusId(composedStatus.getMessageStatusId());
		MessageProcessingHistory mph=messageProcessingHistoryRepository.save(messageProcessingHistory);
		LOGGER.info("logEmail: Message Record added into the messageProcessingHistory Database: {}, uuid={}",mph,uuid);
		//Adding CC's in message_recipient_cc Table
		String[] CC=emailNotificationsDTO.getCc();
		if(CC != null)
			for(String cc:CC){
				MessageRecipientCC messageRecipientCC=new MessageRecipientCC();
				messageRecipientCC.setEmailDomain(cc);
				messageRecipientCC.setMessagesId(m.getMessagesId());
				messageRecipientCCRepository.save(messageRecipientCC);
				LOGGER.info("logReplyEmail: CC Recipient added: {}, uuid={}",cc,uuid);
			}
		//Adding EmailMessage Entry into the EmailMessage  Table
		EmailMessages emailMessage=new EmailMessages();
		emailMessage.setMessageId(m.getMessagesId());
		emailMessage.setSubject(emailNotificationsDTO.getSubject());
		emailMessage.setLanguage("en");
		emailMessage.setBodyHtml(emailNotificationsDTO.getBodyHTML());
		emailMessage.setCreatedBy(emailNotificationsDTO.getCreatedBy());
		emailMessage.setParentEmailMessageId(parentEmailMessageId);
		Party party=partyRepository.getPartyByName(emailNotificationsDTO.getPartyName());
		if(party != null)
		{	LOGGER.info("logReplyEmail: Party Data Retrieved: {}, uuid={}",party,uuid);
			emailMessage.setPartyId(party.getKey());
		}
		emailMessage.setEmailMessageStatusId(createdStatus.getEmailMessageStatusId());
		emailMessage.setCreatedDate(emailNotificationsDTO.getDateSent());
		EmailMessages e=emailMessagesRepository.save(emailMessage);
		LOGGER.info("logEmail: new email message record added to the Database: {}, uuid={}",e,uuid);
		logOutboundAttachments(emailNotificationsDTO.getEmailAttachmentsList(),e.getEmailMessageId(),uuid);
		EmailMessageProcessingHistory emailMessageProcessingHistory=new EmailMessageProcessingHistory();
		emailMessageProcessingHistory.setEmailMessageId(e.getEmailMessageId());
		emailMessageProcessingHistory.setEmailMessageStatusId(createdStatus.getEmailMessageStatusId());
		emailMessageProcessingHistory.setCreatedBy(e.getCreatedBy());
		emailMessageProcessingHistory.setCreatedDate(e.getCreatedDate());
		EmailMessageProcessingHistory emph=emailMessageProcessingHistoryRepository.save(emailMessageProcessingHistory);
		LOGGER.info("logEmail: EMail Message Record added into the EmailMessageProcessingHistory Database: {}, uuid={}",emph,uuid);
		//Adding messageEntry into the EmailExtractionMapping Table
		EmailExtractionMapping emailExtractionMapping=new EmailExtractionMapping();
		emailExtractionMapping.setEmailMessageId(e.getEmailMessageId());
		emailExtractionMapping.setEmailMessageExtractionId(emailMessageExtractionId);
		EmailExtractionMapping emailExtractionMapping1=emailExtractionMappingRepository.save(emailExtractionMapping);
		LOGGER.info("logEmail: EmailExtractionMapping Created: {}, uuid={}",emailExtractionMapping1,uuid);

		return m;
	}

	public void logOutboundAttachments(List<OutboundAttachment> emailAttachmentsList, Integer emailMessageId,UUID uuid) {
		List<EmailAttachments> emailAttachmentsList1 = new ArrayList<>();
		if(emailAttachmentsList != null && !emailAttachmentsList.isEmpty()){
			emailAttachmentsList.stream().forEach(e-> {
				EmailAttachments emailAttachments = new EmailAttachments();
				emailAttachments.setEmailMessageId(emailMessageId);
				emailAttachments.setAttachmentFile(Base64.getDecoder().decode(e.getAttachmentFile()));
				emailAttachments.setFileName(e.getFileName());
				emailAttachments.setCreatedBy(e.getCreatedBy());
				emailAttachments.setCreatedDate(e.getCreatedDate());
				emailAttachments.setFileType(e.getFileType());
				emailAttachments.setFileSize(e.getFileSize());
				emailAttachments.setContentDisposition(e.getContentDisposition());
				emailAttachmentsList1.add(emailAttachments);
			});
		}
		if(!emailAttachmentsList1.isEmpty()) {
			emailAttachmentsRepository.saveAll(emailAttachmentsList1);
			LOGGER.info("logOutboundAttachment: Stored attachments in Database, uuid={}",uuid);
		}
	}


	public ModelApiResponse sendReplyEmail(EmailNotificationsDTO emailNotificationsDTO, UUID uuid) {
		ModelApiResponse modelApiResponse = new ModelApiResponse();
		String response;
		String from=null;
		Integer emailMessageExtractionId=emailMessageExtractionRepository.getEmailMessageExtractionIdByEmailMessageId(emailNotificationsDTO.getEmailMessageId());
		ArrayList<String> senderEmail=new ArrayList<>();
		senderEmail.add("occ-maintenance@one.verizon.com");
		senderEmail.add("idnc-maintenance@one.verizon.com");
		senderEmail.add("ptt-maintenance@one.verizon.com");
		senderEmail.add("nocvendornotify@VerizonWireless.com");
		if(senderEmail.contains(emailNotificationsDTO.getSenderEmail())){
			from=emailNotificationsDTO.getSenderEmail();
		}
		if(from != null && emailMessageExtractionId != null){
			//Replying Email
			LOGGER.info("sendReplyEmail: Started sending the Email Reply, uuid={}",uuid);
			Session javaMailSender = mailConnector.javaMailSender();
			LOGGER.info("sendReplyEmail: Session was created : {}, uuid={}",javaMailSender,uuid);
			//Adding previous Conversations in the Reply
			List<Object[]> mailMessgeQueryList = emailMessagesRepository.getAllMailMessagesByExtractionId(emailNotificationsDTO.getEmailMessageId());
			final String[] previousConversations = {""};
			if(mailMessgeQueryList != null){
				mailMessgeQueryList.forEach(mail-> {
					String fromPrev= "<hr> From: "+mail[0].toString()+"<br>";
					String toPrev="To: "+mail[1].toString()+"<br>";
					String sentDatePrev="Sent: "+mail[2]+"<br>";
					String SubjectPrev="Subject :"+mail[3]+"<br>"+"<br>";
					String previousBody=fromPrev+sentDatePrev+toPrev+SubjectPrev+emailNotificationsDTO.getEditableContent();
					previousConversations[0] = previousConversations[0] +previousBody;
				});
			}
			try{
				if(!emailNotificationsDTO.getSubject().contains("Re: ")){
				emailNotificationsDTO.setSubject("Re: "+emailNotificationsDTO.getSubject());
				}
				if(emailNotificationsDTO.getBodyHTML() != null) {
					emailNotificationsDTO.setBodyHTML(emailNotificationsDTO.getBodyHTML() + previousConversations[0]);
				}
				else{
					emailNotificationsDTO.setBodyHTML(previousConversations[0]);
				}
				Messages m=logEmail(emailNotificationsDTO,uuid);
				MimeMessage message=new MimeMessage(javaMailSender);
				MimeMessageHelper helper=new MimeMessageHelper(message,true);
				helper.setFrom(from);
				helper.setTo(emailNotificationsDTO.getRecipients());
				helper.setSubject(emailNotificationsDTO.getSubject());

				MimeMultipart multipart=new MimeMultipart();
				MimeBodyPart htmlPart=new MimeBodyPart();
				htmlPart.setContent(emailNotificationsDTO.getBodyHTML(),"text/html; charset=utf-8");
				multipart.addBodyPart(htmlPart);
				outboundAttachments(emailNotificationsDTO,multipart,uuid);
				message.setContent(multipart);
				//helper.setText(emailNotificationsDTO.getBodyHTML()+previousConversations[0],true);
				if(emailNotificationsDTO.getCc() != null) {
					helper.setCc(emailNotificationsDTO.getCc());
				}
				if(emailNotificationsDTO.getBcc() != null){
					helper.setBcc(emailNotificationsDTO.getBcc());
				}
				LOGGER.info("sendReplyEmail: Data Inserted into the Helper: {}, uuid={}",helper,uuid);
				Transport.send(message);
				LOGGER.info("sendReplyEmail: Email Sent Successfully, uuid={}",uuid);
				logSentEmail(m,emailNotificationsDTO,uuid);
				LOGGER.info("sendReplyEmail: Email log added to the Database, uuid={}",uuid);
				response= "Email sent successfully";
				modelApiResponse.setMessage(response);
				modelApiResponse.setCode(200);
			}
			catch(MessagingException exc){
				LOGGER.info("sendReplyEmail: Error While sending Message: {}, uuid={}",exc,uuid);
				response=exc.toString();
				modelApiResponse.setMessage(response);
				modelApiResponse.setCode(400);
			}
		}
		else{
			if(from == null) {
				LOGGER.info("sendReplyEmail: Email Sender was not Identified, uuid={}",uuid);
				response = "Email Sender was not Identified";
				modelApiResponse.setMessage(response);
				modelApiResponse.setCode(400);

			}
			else {
				LOGGER.info("sendReplyEmail: Email Extraction Id was not Found, uuid={}",uuid);
				response = "Email Extraction Id is not Found";
				modelApiResponse.setMessage(response);
				modelApiResponse.setCode(400);
			}
		}
		return modelApiResponse;
    }
	public ModelApiResponse sendForwardEmail(EmailNotificationsDTO emailNotificationsDTO,UUID uuid){
		ModelApiResponse modelApiResponse=new ModelApiResponse();
		String response ;
		String from=null;
		Integer emailMessageExtractionId=emailMessageExtractionRepository.getEmailMessageExtractionIdByEmailMessageId(emailNotificationsDTO.getEmailMessageId());
		//checking weather the sender email is valid or not
		ArrayList<String> senderEmail=new ArrayList<>();
		senderEmail.add("occ-maintenance@one.verizon.com");
		senderEmail.add("idnc-maintenance@one.verizon.com");
		senderEmail.add("ptt-maintenance@one.verizon.com");
		senderEmail.add("nocvendornotify@VerizonWireless.com");
		if(senderEmail.contains(emailNotificationsDTO.getSenderEmail())){
			from=emailNotificationsDTO.getSenderEmail();
		}
		if(from != null && emailMessageExtractionId != null){
			//Forwarding Email
			LOGGER.info("sendForwardEmail: Started sending the Email Reply, uuid={}",uuid);
			Session javaMailSender = mailConnector.javaMailSender();
			LOGGER.info("sendForwardEmail: Session was created : {}, uuid={}",javaMailSender,uuid);
			//Adding previous Conversations in the Forward
			List<Object[]> mailMessgeQueryList = emailMessagesRepository.getAllMailMessagesByExtractionId(emailNotificationsDTO.getEmailMessageId());
			final String[] previousConversations = {""};
			if(mailMessgeQueryList != null){
				mailMessgeQueryList.forEach(mail-> {
					String fromPrev= "<hr> From: "+mail[0].toString()+"<br>";
					String toPrev="To: "+mail[1].toString()+"<br>";
					String sentDatePrev="Sent: "+mail[2]+"<br>";
					String SubjectPrev="Subject :"+mail[3]+"<br>"+"<br>";

					String previousBody=fromPrev+sentDatePrev+toPrev+SubjectPrev+emailNotificationsDTO.getEditableContent();
					previousConversations[0] = previousConversations[0] +previousBody;
				});
			}
			try{			if(!emailNotificationsDTO.getSubject().contains("Fwd: ")){
				emailNotificationsDTO.setSubject("Fwd: "+emailNotificationsDTO.getSubject());
			}
			if(emailNotificationsDTO.getBodyHTML() != null) {
				emailNotificationsDTO.setBodyHTML(emailNotificationsDTO.getBodyHTML() + "<br>----------Forwarded Message----------<br>" + previousConversations[0]);
			}
			else {
				emailNotificationsDTO.setBodyHTML("<br>----------Forwarded Message----------<br>" + previousConversations[0]);
			}
				Messages m=logEmail(emailNotificationsDTO,uuid);
				MimeMessage message=new MimeMessage(javaMailSender);
				MimeMessageHelper helper=new MimeMessageHelper(message,true);
				helper.setFrom(from);
				helper.setTo(emailNotificationsDTO.getRecipients());
				helper.setSubject(emailNotificationsDTO.getSubject());
				MimeMultipart multipart=new MimeMultipart();
				MimeBodyPart htmlPart=new MimeBodyPart();
				htmlPart.setContent(emailNotificationsDTO.getBodyHTML(),"text/html; charset=utf-8");
				multipart.addBodyPart(htmlPart);
				outboundAttachments(emailNotificationsDTO,multipart,uuid);
				message.setContent(multipart);
				//helper.setText(emailNotificationsDTO.getBodyHTML()+previousConversations[0],true);
				if(emailNotificationsDTO.getCc() != null) {
					helper.setCc(emailNotificationsDTO.getCc());
				}
				if(emailNotificationsDTO.getBcc() != null){
					helper.setBcc(emailNotificationsDTO.getBcc());
				}
				LOGGER.info("sendForwardEmail: Data Inserted into the Helper: {}, uuid={}",helper,uuid);
				Transport.send(message);
				LOGGER.info("sendForwardEmail: Email Sent Successfully, uuid={}",uuid);
				logSentEmail(m,emailNotificationsDTO,uuid);
				LOGGER.info("sendForwardEmail: Email log added to the Database, uuid={}",uuid);
				response= "Email Forwarded successfully";
				modelApiResponse.setMessage(response);
				modelApiResponse.setCode(200);
			}
			catch(MessagingException exc){
				LOGGER.info("sendForwardEmail: Error While Forwarding Message: {}, uuid={}",exc,uuid);
				response=exc.toString();
				modelApiResponse.setMessage(response);
				modelApiResponse.setCode(400);
			}
		}
		else{
			if(from == null) {
				LOGGER.info("sendForwardEmail: Email Sender was not Identified, uuid={}",uuid);
				response = "Email Sender was not Identified";
				modelApiResponse.setMessage(response);
				modelApiResponse.setCode(400);

			}
			else {
				LOGGER.info("sendForwardEmail: Email Extraction Id was not Found, uuid={}",uuid);
				response = "Email Extraction Id is not Found";
				modelApiResponse.setMessage(response);
				modelApiResponse.setCode(400);
			}
		}
		return modelApiResponse;

	}

	public void outboundAttachments(EmailNotificationsDTO emailNotificationsDTO, MimeMultipart multipart,UUID uuid) {
		try{
			if(emailNotificationsDTO.getEmailAttachmentsList() != null && !emailNotificationsDTO.getEmailAttachmentsList().isEmpty()){
				LOGGER.info("outboundAttachments: Adding Attachments for email, uuid={}",uuid);
				for(OutboundAttachment emailAttachments : emailNotificationsDTO.getEmailAttachmentsList()){
					byte[] byteSource=Base64.getDecoder().decode(emailAttachments.getAttachmentFile());
					DataSource source=new ByteArrayDataSource(byteSource,"application/octet-stream");
					MimeBodyPart attachmentBodyPart=new MimeBodyPart();
					attachmentBodyPart.setDataHandler(new DataHandler(source));
					attachmentBodyPart.setFileName(emailAttachments.getFileName());
					multipart.addBodyPart(attachmentBodyPart);
					LOGGER.info("outboundAttachments: Added Attachments for email, uuid={}",uuid);
				}
			}
		} catch (Exception e){
			LOGGER.error("outboundAttachments: Failed to add Attachments for email, uuid={}",uuid);
		}
	}

	private String updateMessageStatusWithNoActionRequired(EmailMessages emailMessages){
		return  emailMessageStatusRepository.getEmailMessageStatusById(emailMessages.getMessageId());
	}

	private String findEmailType(String subject, String emailMsgStatus) {
		String emailType;
		if (subject.toLowerCase().startsWith(Constants.FORWARD)) {
			emailType = Constants.EMAIL_MESSAGE_STATUS_FORWARDED;
		} else if (subject.toLowerCase().startsWith(Constants.REPLIED)) {
			emailType = Constants.EMAIL_MESSAGE_STATUS_REPLIED;
		} else {
			emailType = emailMsgStatus;
		}
		return emailType;
	}

}

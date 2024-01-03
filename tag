java: cannot access jakarta.mail.internet.MimeMessage
  class file for jakarta.mail.internet.MimeMessage not found
dependencies {
    // Other dependencies...
    implementation 'jakarta.mail:jakarta.mail-api:1.6.7' // Replace with the appropriate version
}
				MimeMessageHelper helper=new MimeMessageHelper(message,true);


Cannot resolve constructor 'MimeMessageHelper(MimeMessage, boolean)'
-------
dependencies {
    implementation 'jakarta.mail:jakarta.mail-api:1.7.5' // Replace version with appropriate one
    // other dependencies...
}
import javax.mail.internet.MimeMessage;
import javax.mail.MessagingException;
import jakarta.mail.internet.MimeMessage;
import jakarta.mail.MessagingException;

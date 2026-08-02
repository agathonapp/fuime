# frozen_string_literal: true

class CommentMailer < ApplicationMailer
  def notification
    @comment = params[:comment]
    @commentable = @comment.commentable

    return if @commentable.comment_recipients_for(@comment).empty?

    # the bank@hackclub.com is used for automated comments,
    # for now, these automated comments won't notify users.
    # see OneTimeJobs::BackfillLostReceipts for an example
    # - @sampoder
    return if @comment.user == User.system_user

    return unless @comment.content || @comment.file

    mail_settings = {
      bcc: @commentable.comment_recipients_for(@comment),
      # Fuime: was comments+...@hcb.hackclub.com, which routed Fuime users'
      # replies into Hack Club's inbound parser — a privacy leak to a third
      # party and a broken reply path for us. Inbound comment parsing is not
      # yet wired up on the Fuime domain, so replies bounce rather than
      # silently going somewhere they shouldn't.
      reply_to: "comments+#{@comment.public_id}@#{ApplicationMailer::DOMAIN}",
      subject: @commentable.comment_mailer_subject,
      template_path: "comment_mailer/#{@commentable.class.name.underscore}",
      from: email_address_with_name(ApplicationMailer::OPERATIONS_EMAIL, "#{@comment.user.name} via Fuime")
    }.merge(headers)

    mail(mail_settings)
  end

  def bounce_missing_comment
    mail subject: @inbound_mail&.mail&.subject || "Unknown comment", to: @inbound_mail&.mail&.from&.first
  end

  private

  def headers
    {
      in_reply_to: thread_id(@commentable),
      message_id: message_id(@comment),
      references: @commentable.comments.map { |c| message_id(c) }.join(" ")
    }.compact_blank
  end

  def message_id(comment)
    # "<comment-cmt_Sl3ns3@fuime.com>" — threading identifier, must be on a
    # Fuime domain so threads don't collide with upstream Fuime's.
    "<comment-#{comment.public_id}@#{ApplicationMailer::DOMAIN}>"
  end

  def thread_id(commentable)
    first_comment = commentable.comments.first
    message_id(first_comment)
  end

end

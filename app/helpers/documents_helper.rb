# frozen_string_literal: true

module DocumentsHelper
  # Fuime: display names for `Document#category`.
  #
  # The enum keys are upstream HCB's and stay as they are — `category` is a
  # stored integer and the keys are load-bearing (CLAUDE.md Rule 6), so this
  # renames the words a founder reads and nothing else.
  #
  # Two of the five described a 501(c)(3) that Fuime ventures are not.
  # "Nonprofit status" and "Tax-exemption documents" are fiscal-sponsorship
  # artifacts — an IRS determination letter, a state exemption certificate —
  # and a teen business has none of them. They are relabelled rather than
  # removed because the buckets still hold the documents a small business
  # actually files: formation paperwork and an EIN letter in one, a W-9 or a
  # 1099-K in the other. Removing the sections would have hidden anything
  # already uploaded into them.
  CATEGORY_LABELS = {
    "general"          => "General documents",
    "nonprofit_status" => "Business registration",
    "tax_exemption"    => "Tax documents",
    "forms"            => "Forms",
    "contracts"        => "Contracts"
  }.freeze

  def document_category_label(category)
    CATEGORY_LABELS.fetch(category.to_s, category.to_s.humanize)
  end

  # `[label, value]` pairs for the upload form, so the admin picking a bucket
  # and the founder reading the page see the same word.
  def document_category_options
    Document.categories.keys.map { |key| [document_category_label(key), key] }
  end
end

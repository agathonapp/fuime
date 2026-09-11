# frozen_string_literal: true

module MockTransactionEngineService
  class GenerateMockTransaction
    # Fuime: income + the platform take-rate only. Family MoR has no operator
    # spend rail (Issuing off, reimbursements hidden), so random negative
    # "supply/card" lines imply a debit card Maya does not have. Upstream's
    # club-and-donation copy ("Fiscal sponsorship fee", discos, stranger
    # donations) is the product Fuime is explicitly not.
    SERVICE_FEE_RATE = Event::Plan::Free::REVENUE_FEE
    SERVICE_FEE_LABEL = "Fuime service fee (#{(SERVICE_FEE_RATE * 100).to_i}%)".freeze

    POSITIVE_DESCRIPTIONS = [
      { desc: "Lawn — Saturday block" },
      { desc: "Weekly lawn subscription", monthly: true },
      { desc: "Hedge trim — weekend visit" },
      { desc: "Tutoring — algebra, 1 hour" },
      { desc: "Tutoring — weekly sessions", monthly: true },
    ].freeze

    def initialize
      @mock_tx_num = rand(7..10)
      @mock_balance = 0
    end

    def run
      generate_mock_transaction_list.map do |trans|
        mock_transaction(trans)
      end
    end

    # `memo` is defined as a singleton method rather than an OpenStruct field
    # because the views call it both ways — `memo` and `memo(event:)` (see
    # hcb_codes/memo/_memo.html.erb). A plain field is arity 0 and raises
    # ArgumentError on the second form, which is what made the restored mock
    # ledger 500 on first run.
    def mock_transaction(trans)
      hcb_code = mock_hcb_code(trans)

      OpenStruct.new(
        amount: Money.new(trans[:amount].round(2) * 100),
        amount_cents: (trans[:amount].round(2) * 100).to_i,
        fee_payment?: trans[:desc].include?("Fuime service fee"),
        date: trans[:date],
        local_hcb_code: hcb_code
      )
    end

    def mock_hcb_code(trans)
      OpenStruct.new(
        receipts: [],
        comments: [],
        # `donation?`/`donation` stay: the transaction partial calls them on
        # every row, so these are interface, not copy.
        donation?: trans[:amount].positive?,
        donation: trans[:amount].positive? ? OpenStruct.new(recurring?: trans[:monthly]) : nil,
        tags: [],
        reimbursement_expense_payout?: false,
        # `custom_memo` non-nil on purpose. hcb_codes/memo/_memo caches the
        # rendered memo under "#{event}/#{hcb_code.hcb_code}/cached_memo"
        # when it is nil — and a mock row has no hcb_code, so every row
        # collided on one key and the whole ledger rendered the same memo
        # (cached for ten minutes, across requests). Setting it takes the
        # uncached branch, which is what mock data wants anyway.
        custom_memo: trans[:desc]
      ).tap do |hcb_code|
        # Singleton methods, not fields, wherever the views pass arguments: an
        # OpenStruct field is arity 0 and raises ArgumentError on a call with
        # any. These are the calls canonical_transactions/_canonical_transaction
        # and hcb_codes/memo/_memo make on every row.
        hcb_code.define_singleton_method(:memo) { |event: nil| trans[:desc] }
        hcb_code.define_singleton_method(:not_admin_only_comments_count) { comments.size }
        hcb_code.define_singleton_method(:association) { |_name| OpenStruct.new(reader: receipts) }
        hcb_code.define_singleton_method(:receipt_optional?) { |*| true }
        hcb_code.define_singleton_method(:missing_receipt?) { |*| false }
      end
    end

    def generate_mock_sale
      POSITIVE_DESCRIPTIONS[rand(POSITIVE_DESCRIPTIONS.length)].merge({ amount: rand(40.0..180.0) })
    end

    def generate_mock_service_fee(sale_amount)
      { desc: SERVICE_FEE_LABEL, amount: -SERVICE_FEE_RATE * sale_amount }
    end

    def generate_mock_transaction_list
      @mock_tx = []
      while @mock_tx.length < @mock_tx_num
        sale = generate_mock_sale
        fee = generate_mock_service_fee(sale[:amount])
        @mock_tx << sale
        @mock_tx << fee
        @mock_balance += sale[:amount] + fee[:amount]
      end

      current_date = DateTime.now
      pairs = @mock_tx.each_slice(2).to_a
      pairs.reverse_each do |sale, fee|
        sale[:date] = current_date.strftime("%Y-%m-%d")
        current_date -= rand(8..180)
        fee[:date] = current_date.strftime("%Y-%m-%d")
        current_date -= 7
      end

      pairs.reverse.flatten
    end

  end
end

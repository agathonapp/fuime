# frozen_string_literal: true

module MockTransactionEngineService
  class GenerateMockTransaction
    # Fuime: rewritten from upstream's club-and-donation copy. The originals
    # described a fiscally sponsored nonprofit — "Fiscal sponsorship fee",
    # donations from strangers, club discos — which is the product Fuime is
    # explicitly not (CLAUDE.md, and docs/fuime/BRAND_STRINGS.md on user-facing
    # strings). These are a teen business's costs and takings instead.
    NEGATIVE_DESCRIPTIONS = [
      { desc: "📦 Packaging and mailers (bulk)" },
      { desc: "🧵 Filament restock — 6 spools" },
      { desc: "🎪 Farmers market booth fee" },
      { desc: "🛒 Restaurant Depot — flour, butter, chocolate" },
      { desc: "🖨️ Sticker printing (500 count)" },
      { desc: "🚲 Delivery bike repair" },
      { desc: "📸 Product photos for the shop page" },
      { desc: "🧼 Cleaning supplies for the kitchen" },
      { desc: "🏷️ Labels and hang tags" },
      { desc: "☕ Coffee for a 6am prep shift" },
      { desc: "🧾 Business cards" },
      { desc: "🔌 Extension cords for the market stall" },
      { desc: "🪧 A-frame sign for the sidewalk" },
      { desc: "🧊 Ice for the cooler" },
      { desc: "📱 Card reader for in-person sales" },
      { desc: "🎨 Logo design (traded for cookies, mostly)" },
      { desc: "🚚 Shipping to the wholesale account" },
      { desc: "🧰 Replacement mixer paddle" },
    ].freeze
    POSITIVE_DESCRIPTIONS = [
      { desc: "🛍️ Online store payout" },
      { desc: "🤝 Wholesale order — Ridge Coffee", monthly: true },
      { desc: "🎪 Farmers market — Saturday takings" },
      { desc: "🎂 Custom order deposit" },
      { desc: "🔁 Weekly subscription boxes", monthly: true },
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
        fee_payment?: trans[:desc].include?("Fuime platform fee"),
        date: trans[:date],
        local_hcb_code: hcb_code
      )
    end

    def mock_hcb_code(trans)
      OpenStruct.new(
        receipts: if trans[:amount] > 0 || trans[:desc].include?("Fuime platform fee")
                    []
                  else
                    Array.new(rand(100) < 90 ? 1 : 0)
                  end, # 90% chance of 1 receipt, 10% chance of no receipts
        comments: Array.new(rand(9) > 1 || trans[:desc].include?("Fuime platform fee") ? 0 : rand(1..2)), # 1/3 chance of no comments, 2/3 chance of 1 or 2 comments
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
        hcb_code.define_singleton_method(:receipt_optional?) { |*| trans[:amount].positive? }
        hcb_code.define_singleton_method(:missing_receipt?) { |*| trans[:amount].negative? && receipts.empty? }
      end
    end

    def generate_mock_tx
      NEGATIVE_DESCRIPTIONS[rand(NEGATIVE_DESCRIPTIONS.length)].merge({ amount: rand(0..@mock_balance) * -1 })
    end

    def generate_mock_sale
      POSITIVE_DESCRIPTIONS[rand(POSITIVE_DESCRIPTIONS.length)].merge({ amount: rand(1000) })
    end

    def generate_mock_platform_fee(sale_amount)
      { desc: "Fuime platform fee (4%)", amount: -0.04 * sale_amount }
    end

    def generate_mock_transaction_list
      @mock_tx = []
      index = 0
      while index < @mock_tx_num
        if @mock_balance > rand(1..40)
          @mock_tx << generate_mock_tx
          @mock_balance += @mock_tx[index][:amount] # add the negative transaction amount to the balance
          index += 1
        else # else, generate a random sale
          @mock_tx << generate_mock_sale
          @mock_tx << generate_mock_platform_fee(@mock_tx.last[:amount])
          @mock_balance += @mock_tx[index][:amount] # add the sale amount to the balance
          @mock_balance += @mock_tx.last[:amount] # add the negative fiscal fee amount to the balance
          index += 2 # increment the index by 2 to account for the sale and the fee
        end
      end

      current_date = DateTime.now
      @mock_tx.reverse.each do |tx|
        random_interval = tx[:desc].include?("Fuime platform fee") ? 7 : rand(8..180) # If the transaction is not a fiscal sponsorship fee, generate a random interval between 8 and 180 days
        tx[:date] = current_date.strftime("%Y-%m-%d") # Format the date
        current_date -= random_interval # Increment the date by the random interval, or 7 if the transaction is a fiscal sponsorship fee
      end

      @mock_tx.reverse
    end

  end
end

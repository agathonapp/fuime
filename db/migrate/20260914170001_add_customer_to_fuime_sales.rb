# frozen_string_literal: true

# Fuime: point a sale at who bought it.
#
# Its own migration because `add_index` on an existing table takes a write lock
# for the duration of the build, and the house rule (Strong Migrations) is to do
# that concurrently — which requires `disable_ddl_transaction!` and therefore
# cannot share a migration with CreateFuimeCustomers' table creation.
#
# No foreign key, for the reason `fuime_sales.fuime_offer_id` has none: a sale is
# a fact about money that changed hands, and it must survive anything else being
# removed by any route.
class AddCustomerToFuimeSales < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :fuime_sales, :fuime_customer_id, :bigint
    add_index :fuime_sales, :fuime_customer_id, algorithm: :concurrently
  end

end

module Spree
  module ActiveShipping
    module CanadaPostPWSOverride
      def self.included(base)
        def initialize(options = {})
          @contract_id = options[:contract_id]

          super(options)
        end

        base.class_eval do
          cattr_reader :name

          attr_accessor :contract_id

          def self.default_location
            ActiveMerchant::Shipping::Location.new(
              country: 'CA',
              zip: 'K2B8J6'
            )
          end

          def headers(customer_credentials, accept = nil, content_type = nil)
            headers = {
              'Authorization'   => encoded_authorization(customer_credentials),
              'Accept-Language' => language
            }
            headers['Accept'] = accept if accept
            headers['Content-Type'] = content_type if content_type
            headers['Platform-Id'] = platform_id if platform_id

            headers
          end

          def valid_credentials?
            location = self.class.default_location
            find_rates(
              location,
              location,
              ActiveMerchant::Shipping::Package.new(100, [10,10,10], units: :metric)
            )
          rescue ActiveMerchant::Shipping::ResponseError, ::ActiveShipping::ResponseError
            false
          else
            true
          end

          # Override the method to allow the use of multiple packages.
          # Each line item is a package (ActiveMerchant::Shipping::Package),
          # as Canada Post does not allow sending multiple packages when
          # fetching the services we need to make a request for each package.
          def find_rates(origin, destination, line_items = [], options = {}, package = nil, services = [])
            Spree::ActiveShipping::CanadaPostPws::ShippingRates.call(
              carrier: self,
              origin: origin,
              destination: destination,
              packages: line_items,
              options: options,
              package: package,
              services: services
            )
          rescue ActiveMerchant::ResponseError, ActiveMerchant::Shipping::ResponseError => e
            error_response(e.response.body, ActiveMerchant::Shipping::CPPWSRateResponse)
          end

          def contract_id_node(options)
            return unless options[:contract_id] || contract_id.present?

            XmlNode.new('contract-id', options[:contract_id] || contract_id)
          end

          def parcel_node(line_items, package = nil, options = {})
            weight = sanitize_weight_kg(package && !package.kilograms.zero? ? package.kilograms.to_f : line_items.sum(&:kilograms).to_f)

            XmlNode.new('parcel-characteristics') do |el|
              el << XmlNode.new('weight', '%#2.3f' % weight)

              pkg_dim = package.try(:cm) || line_items.first.cm
              if pkg_dim && !pkg_dim.select { |x| x != 0 }.empty?
                el << XmlNode.new('dimensions') do |dim|
                  dim << XmlNode.new('length', '%.1f' % ((pkg_dim[2] * 10).round / 10.0)) if pkg_dim.size >= 3
                  dim << XmlNode.new('width', '%.1f' % ((pkg_dim[1] * 10).round / 10.0)) if pkg_dim.size >= 2
                  dim << XmlNode.new('height', '%.1f' % ((pkg_dim[0] * 10).round / 10.0)) if pkg_dim.size >= 1
                end
              end

              el << XmlNode.new('mailing-tube', line_items.any?(&:tube?))
              el << XmlNode.new('oversized', true) if line_items.any?(&:oversized?)
              el << XmlNode.new('unpackaged', line_items.any?(&:unpackaged?))
            end
          end
        end
      end
    end
  end
end


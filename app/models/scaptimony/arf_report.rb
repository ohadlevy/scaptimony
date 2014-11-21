require 'fileutils'
require 'openscap'
require 'openscap/ds/arf'
require 'openscap/xccdf/testresult'
require 'openscap/xccdf/ruleresult'
require 'scaptimony/engine'

module Scaptimony
  class ArfReport < ActiveRecord::Base
    belongs_to :asset
    belongs_to :policy
    has_many :xccdf_rule_results, :dependent => :destroy

    before_destroy { |record|
      record.delete
    }

    def store!(data)
      begin
        FileUtils.mkdir_p dir
        File.open(path, 'wb') { |f| f.write(data) }
        save_dependent_entities
      rescue StandardError => e
        logger.error "Could not store ARF to '#{path}': #{e.message}"
        raise e
      end
    end

    def each
      OpenSCAP.oscap_init
      arf = OpenSCAP::DS::Arf.new path
      yield arf.html
      arf.destroy
      OpenSCAP.oscap_cleanup
    end

    def delete
      File.delete path
      begin
        Dir.delete dir
      rescue StandardError => e
      end
    end

    private
    def save_dependent_entities
      begin
        OpenSCAP.oscap_init
        arf = OpenSCAP::DS::Arf.new path
        test_result = arf.test_result
        test_result.rr.each {|rr_id, rr|
          rule = ::Scaptimony::XccdfRule.where(:xid => rr_id).first_or_create!
          self.xccdf_rule_results.create!(:xccdf_rule_id => rule.id, :xccdf_result_id => XccdfResult.f(rr.result).id)
        }
      rescue StandardError => e
        self.xccdf_rule_results.destroy_all
        raise e
      ensure
        test_result.destroy unless test_result.nil?
        arf.destroy unless arf.nil?
        OpenSCAP.oscap_cleanup
      end
    end

    def path
      "#{dir}/#{digest}.xml.bz2"
    end

    def dir
      # TODO this should be configurable
      "#{Scaptimony::Engine.dir}/arf/#{asset.name}/#{policy.name}/#{date}"
    end
  end
end

require 'securerandom'
module RubySMB
  class Client
    # This module holds all of the methods backing the {RubySMB::Client#negotiate} method
    module Negotiation
      # Handles the entire SMB Multi-Protocol Negotiation from the
      # Client to the Server. It sets state on the client appropriate
      # to the protocol and capabilites negotiated during the exchange.
      # It also keeps track of the negotiated dialect.
      #
      # @return [void]
      def negotiate
        request_packet  = negotiate_request
        raw_response    = send_recv(request_packet)
        response_packet = negotiate_response(raw_response)
        # The list of dialect identifiers sent to the server is stored
        # internally to be able to retrieve the negotiated dialect later on.
        # This is only valid for SMB1.
        response_packet.dialects = request_packet.dialects if response_packet.respond_to? :dialects=
        parse_negotiate_response(response_packet)
      rescue RubySMB::Error::InvalidPacket, Errno::ECONNRESET
        error = 'Unable to Negotiate with remote host'
        error << ', SMB1 may be disabled' if smb1 && !smb2
        raise RubySMB::Error::NegotiationFailure, error
      end

      # Creates the first Negotiate Request Packet according to the SMB version
      # used.
      #
      # @return [RubySMB::SMB1::Packet::NegotiateRequest] a SMB1 Negotiate Request packet if SMB1 is used
      # @return [RubySMB::SMB1::Packet::NegotiateRequest] a SMB2 Negotiate Request packet if SMB2 is used
      def negotiate_request
        if smb1
          smb1_negotiate_request
        elsif smb2
          smb2_negotiate_request
        end
      end

      # Takes the raw response data from the server and tries
      # parse it into a valid Response packet object.
      # This method currently assumes that all SMB1 will use Extended Security.
      #
      # @param raw_data [String] the raw binary response from the server
      # @return [RubySMB::SMB1::Packet::NegotiateResponseExtended] when the response is an SMB1 Extended Security Negotiate Response Packet
      # @return [RubySMB::SMB2::Packet::NegotiateResponse] when the response is an SMB2 Negotiate Response Packet
      def negotiate_response(raw_data)
        response = nil
        if smb1
          begin
            packet = RubySMB::SMB1::Packet::NegotiateResponseExtended.read raw_data
          rescue StandardError => e
            raise RubySMB::Error::InvalidPacket, "Not a Valid SMB1 Negoitate Response #{e.message}"
          end
          response = packet if packet.valid?
        end
        if smb2 && response.nil?
          begin
            packet = RubySMB::SMB2::Packet::NegotiateResponse.read raw_data
          rescue StandardError => e
            raise RubySMB::Error::InvalidPacket, "Not a Valid SMB2 Negoitate Response #{e.message}"
          end
          response = packet
        end
        if response.nil?
          raise RubySMB::Error::InvalidPacket, 'No Valid Negotiate Response found'
        end
        response
      end

      # Sets the supported SMB Protocol and whether or not
      # Signing is enabled based on the Negotiate Response Packet.
      # It also stores the negotiated dialect.
      #
      # @param packet [RubySMB::SMB1::Packet::NegotiateResponseExtended] if SMB1 was negotiated
      # @param packet [RubySMB::SMB2::Packet::NegotiateResponse] if SMB2 was negotiated
      # @return [String] The SMB version as a string ('SMB1', 'SMB2')
      def parse_negotiate_response(packet)
        case packet
        when RubySMB::SMB1::Packet::NegotiateResponseExtended
          self.smb1 = true
          self.smb2 = false
          self.signing_required = packet.parameter_block.security_mode.security_signatures_required == 1
          self.dialect = packet.negotiated_dialect.to_s
          self.server_max_buffer_size = packet.parameter_block.max_buffer_size
          'SMB1'
        when RubySMB::SMB2::Packet::NegotiateResponse
          self.smb1 = false
          self.smb2 = true
          self.signing_required = packet.security_mode.signing_required == 1
          self.dialect = "0x%04x" % packet.dialect_revision
          self.server_max_buffer_size = 16644
          'SMB2'
        end

      end

      # Create a {RubySMB::SMB1::Packet::NegotiateRequest} packet with the
      # dialects filled in based on the protocol options set on the Client.
      #
      # @return [RubySMB::SMB1::Packet::NegotiateRequest] a completed SMB1 Negotiate Request packet
      def smb1_negotiate_request
        packet = RubySMB::SMB1::Packet::NegotiateRequest.new
        # Default to always enabling Extended Security. It simplifies the Negotiation process
        # while being gauranteed to work with any modern Windows system. We can get more sophisticated
        # with switching this on and off at a later date if the need arises.
        packet.smb_header.flags2.extended_security = 1
        # There is no real good reason to ever send an SMB1 Negotiate packet
        # to Negotiate strictly SMB2, but the protocol WILL support it
        packet.add_dialect(SMB1_DIALECT_SMB1_DEFAULT) if smb1
        packet.add_dialect(SMB1_DIALECT_SMB2_DEFAULT) if smb2
        packet
      end

      # Create a {RubySMB::SMB2::Packet::NegotiateRequest} packet with
      # the default dialect added. This will never be used when we
      # may want to communicate over SMB1
      #
      # @ return [RubySMB::SMB2::Packet::NegotiateRequest] a completed SMB2 Negotiate Request packet
      def smb2_negotiate_request
        packet = RubySMB::SMB2::Packet::NegotiateRequest.new
        packet.security_mode.signing_enabled = 1
        packet.add_dialect(SMB2_DIALECT_DEFAULT)
        packet.client_guid = SecureRandom.random_bytes(16)
        packet
      end
    end
  end
end

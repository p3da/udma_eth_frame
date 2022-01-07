/**
 * Author: David Pernerstorfer <es20m012@technikum-wien.at>
 * Date: 2022-01-03
 * Description: connects the AXIS RX an TX channel from ethernet mac to pulpissimo udma
 */

module udma_eth_frame #(
    parameter L2_AWIDTH_NOAL = 12,
    parameter TRANS_SIZE     = 16
) (
    input  logic                      sys_clk_i,
    input  logic                      clk_eth,
    input  logic                      clk_eth90,
    input  logic                      rst_eth,
    input  logic   	                  rstn_i,

    input  logic               [31:0] cfg_data_i,
    input  logic                [4:0] cfg_addr_i,
    input  logic                      cfg_valid_i,
    input  logic                      cfg_rwn_i,
    output logic                      cfg_ready_o,
    output logic               [31:0] cfg_data_o,

    output logic [L2_AWIDTH_NOAL-1:0] cfg_rx_startaddr_o,
    output logic     [TRANS_SIZE-1:0] cfg_rx_size_o,
    output logic                      cfg_rx_continuous_o,
    output logic                      cfg_rx_en_o,
    output logic                      cfg_rx_clr_o,
    input  logic                      cfg_rx_en_i,
    input  logic                      cfg_rx_pending_i,
    input  logic [L2_AWIDTH_NOAL-1:0] cfg_rx_curr_addr_i,
    input  logic     [TRANS_SIZE-1:0] cfg_rx_bytes_left_i,

    output logic [L2_AWIDTH_NOAL-1:0] cfg_tx_startaddr_o,
    output logic     [TRANS_SIZE-1:0] cfg_tx_size_o,
    output logic                      cfg_tx_continuous_o,
    output logic                      cfg_tx_en_o,
    output logic                      cfg_tx_clr_o,
    input  logic                      cfg_tx_en_i,
    input  logic                      cfg_tx_pending_i,
    input  logic [L2_AWIDTH_NOAL-1:0] cfg_tx_curr_addr_i,
    input  logic     [TRANS_SIZE-1:0] cfg_tx_bytes_left_i,

    output logic                      data_tx_req_o,
    input  logic                      data_tx_gnt_i,
    output logic                [1:0] data_tx_datasize_o,
    input  logic               [31:0] data_tx_i,
    input  logic                      data_tx_valid_i,
    output logic                      data_tx_ready_o,

    output logic                [1:0] data_rx_datasize_o,
    output logic               [31:0] data_rx_o,
    output logic                      data_rx_valid_o,
    input  logic                      data_rx_ready_i,

    output logic                [7:0] eth_tx_axis_tdata,
    output logic                      eth_tx_axis_tvalid,
    input  logic                      eth_tx_axis_tready,
    output logic                      eth_tx_axis_tlast,
    output logic                      eth_tx_axis_tuser,

    input  logic                [7:0] eth_rx_axis_tdata,
    input  logic                      eth_rx_axis_tvalid,
    output logic                      eth_rx_axis_tready,
    input  logic                      eth_rx_axis_tlast,
    input  logic                      eth_rx_axis_tuser
);

/* signals between tx buffer fifo and dc fifo */
logic           s_data_tx_valid;
logic           s_data_tx_ready;
logic     [7:0] s_data_tx;
logic     [7:0] s_data_rx_o;

assign data_tx_datasize_o = 2'b00;
assign data_rx_datasize_o = 2'b00;

assign data_rx_o = { 24'h0, s_data_rx_o };

/* register interface */
udma_eth_frame_reg #(
    .L2_AWIDTH_NOAL(L2_AWIDTH_NOAL),
    .TRANS_SIZE(TRANS_SIZE)
) u_reg_if (
    .clk_i              ( sys_clk_i           ),
    .rstn_i             ( rstn_i              ),

    .cfg_data_i         ( cfg_data_i          ),
    .cfg_addr_i         ( cfg_addr_i          ),
    .cfg_valid_i        ( cfg_valid_i         ),
    .cfg_rwn_i          ( cfg_rwn_i           ),
    .cfg_ready_o        ( cfg_ready_o         ),
    .cfg_data_o         ( cfg_data_o          ),

    .cfg_rx_startaddr_o ( cfg_rx_startaddr_o  ),
    .cfg_rx_size_o      ( cfg_rx_size_o       ),
    .cfg_rx_continuous_o( cfg_rx_continuous_o ),
    .cfg_rx_en_o        ( cfg_rx_en_o         ),
    .cfg_rx_clr_o       ( cfg_rx_clr_o        ),
    .cfg_rx_en_i        ( cfg_rx_en_i         ),
    .cfg_rx_pending_i   ( cfg_rx_pending_i    ),
    .cfg_rx_curr_addr_i ( cfg_rx_curr_addr_i  ),
    .cfg_rx_bytes_left_i( cfg_rx_bytes_left_i ),

    .cfg_tx_startaddr_o ( cfg_tx_startaddr_o  ),
    .cfg_tx_size_o      ( cfg_tx_size_o       ),
    .cfg_tx_continuous_o( cfg_tx_continuous_o ),
    .cfg_tx_en_o        ( cfg_tx_en_o         ),
    .cfg_tx_clr_o       ( cfg_tx_clr_o        ),
    .cfg_tx_en_i        ( cfg_tx_en_i         ),
    .cfg_tx_pending_i   ( cfg_tx_pending_i    ),
    .cfg_tx_curr_addr_i ( cfg_tx_curr_addr_i  ),
    .cfg_tx_bytes_left_i( cfg_tx_bytes_left_i )
);


io_tx_fifo #(
    .DATA_WIDTH(8),
    .BUFFER_DEPTH(128)
) u_fifo (
    .clk_i   ( sys_clk_i       ),
    .rstn_i  ( rstn_i          ),
    .clr_i   ( 1'b0            ),
    .data_o  ( s_data_tx       ),
    .valid_o ( s_data_tx_valid ),
    .ready_i ( s_data_tx_ready ),
    .req_o   ( data_tx_req_o   ),
    .gnt_i   ( data_tx_gnt_i   ),
    .valid_i ( data_tx_valid_i ),
    .data_i  ( data_tx_i[7:0]  ),
    .ready_o ( data_tx_ready_o )
);

udma_dc_fifo #(
    .DATA_WIDTH(8),
    .BUFFER_DEPTH(128)
) u_dc_fifo_tx (
    .src_clk_i    ( sys_clk_i          ),
    .src_rstn_i   ( rstn_i             ),
    .src_data_i   ( s_data_tx          ),
    .src_valid_i  ( s_data_tx_valid    ),
    .src_ready_o  ( s_data_tx_ready    ),
    .dst_clk_i    ( clk_eth            ),
    .dst_rstn_i   ( rst_eth            ),
    .dst_data_o   ( eth_tx_axis_tdata  ),
    .dst_valid_o  ( eth_tx_axis_tvalid ),
    .dst_ready_i  ( eth_tx_axis_tready )
);

udma_dc_fifo #(
    .DATA_WIDTH(8),
    .BUFFER_DEPTH(128)
) u_dc_fifo_rx (
    .src_clk_i    ( clk_eth            ),
    .src_rstn_i   ( rst_eth            ),
    .src_data_i   ( eth_rx_axis_tdata  ),
    .src_valid_i  ( eth_rx_axis_tvalid ),
    .src_ready_o  ( eth_rx_axis_tready ),
    .dst_clk_i    ( sys_clk_i          ),
    .dst_rstn_i   ( rstn_i             ),
    .dst_data_o   ( s_data_rx_o        ),
    .dst_valid_o  ( data_rx_valid_o    ),
    .dst_ready_i  ( data_rx_ready_i    )
);



endmodule

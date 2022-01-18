/**
 * Author: David Pernerstorfer <es20m012@technikum-wien.at>
 * Date: 2022-01-03
 * Description: connects the AXIS RX an TX channel from ethernet mac to pulpissimo udma
 */

module udma_eth_frame #(
    parameter L2_AWIDTH_NOAL = 12,
    parameter TRANS_SIZE     = 16,

    parameter TX_FIFO_BUFFER_DEPTH = 2048,
    parameter RX_FIFO_BUFFER_DEPTH = 2048,
    parameter RX_FIFO_BUFFER_DEPTH_LOG = $clog2(RX_FIFO_BUFFER_DEPTH)
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

/* udma peripheral uses 16bit data words */
assign data_tx_datasize_o = 2'b01;
assign data_rx_datasize_o = 2'b00;

/* signals between tx buffer fifo and dc fifo */
logic            s_data_tx_valid;
logic            s_data_tx_ready;
logic     [15:0] s_data_tx;

/* signal between tx dc fifo buffer and axis output */
logic     [15:0] s_data_tx_out;

/* signal between axis rx input and rx dc fifo buffer */
logic     [15:0] s_data_rx_in;


/* 16 bit word from fifo must be converted to 32 bit (zero padded) */
logic     [7:0] s_data_rx_o;
assign data_rx_o = { 24'h0, s_data_rx_o };

/* signals between rx dc fifo and generic fifo */
logic            s_data_rx_valid;
logic            s_data_rx_ready;
logic     [15:0] s_data_rx;

logic            s_data_rx_valid_fifo_in;
logic            s_data_rx_ready_fifo_out;

/* writes rx blocked status to register */
logic            cfg_rx_set_blocked;

/* blocked status from register ETH_FRAME_RX_CFG */
logic            cfg_rx_blocked;

/* writes rx status to register */
logic            cfg_rx_set_eof;

logic [RX_FIFO_BUFFER_DEPTH_LOG:0] cfg_rx_fifo_elements;

/* register interface */
udma_eth_frame_reg #(
    .L2_AWIDTH_NOAL(L2_AWIDTH_NOAL),
    .TRANS_SIZE(TRANS_SIZE),
    .RX_FIFO_BUFFER_DEPTH(RX_FIFO_BUFFER_DEPTH)
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
    .cfg_tx_bytes_left_i( cfg_tx_bytes_left_i ),

    .cfg_rx_set_blocked_i    ( cfg_rx_set_blocked   ),
    .cfg_rx_blocked_o     ( cfg_rx_blocked    ),
    .cfg_rx_set_eof_i (cfg_rx_set_eof),

    .cfg_rx_fifo_elements (cfg_rx_fifo_elements)

);

/* tx fifos */
io_tx_fifo #(
    .DATA_WIDTH(16),
    .BUFFER_DEPTH(TX_FIFO_BUFFER_DEPTH)
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
    .data_i  ( data_tx_i[15:0]  ),
    .ready_o ( data_tx_ready_o )
);

udma_dc_fifo #(
    .DATA_WIDTH(16),
    .BUFFER_DEPTH(TX_FIFO_BUFFER_DEPTH)
) u_dc_fifo_tx (
    .src_clk_i    ( sys_clk_i           ),
    .src_rstn_i   ( rstn_i              ),
    .src_data_i   ( s_data_tx           ),
    .src_valid_i  ( s_data_tx_valid     ),
    .src_ready_o  ( s_data_tx_ready     ),
    .dst_clk_i    ( clk_eth             ),
    .dst_rstn_i   ( rst_eth             ),
    .dst_data_o   ( s_data_tx_out       ),
    .dst_valid_o  ( eth_tx_axis_tvalid  ),
    .dst_ready_i  ( eth_tx_axis_tready  )
);

/* the leftmost 8 bits are only used for "last" signaling */
assign eth_tx_axis_tdata =  s_data_tx_out[7:0];
assign eth_tx_axis_tlast = s_data_tx_out[8];

///////////////////////////////////
/////////////// RX ////////////////
///////////////////////////////////
/* rx fifo */
/* store tlast signal at bit 8 */
assign s_data_rx_in = {7'h0, eth_rx_axis_tlast, eth_rx_axis_tdata};

udma_dc_fifo #(
    .DATA_WIDTH(16),
    .BUFFER_DEPTH(RX_FIFO_BUFFER_DEPTH)
) u_dc_fifo_rx (
    .src_clk_i    ( clk_eth            ),
    .src_rstn_i   ( rst_eth            ),
    .src_data_i   ( s_data_rx_in       ),
    .src_valid_i  ( eth_rx_axis_tvalid ),
    .src_ready_o  ( eth_rx_axis_tready ),
    .dst_clk_i    ( sys_clk_i          ),
    .dst_rstn_i   ( rstn_i             ),
    .dst_data_o   ( s_data_rx        ),
    .dst_valid_o  ( s_data_rx_valid    ),
    .dst_ready_i  ( s_data_rx_ready    )
);

assign s_data_rx_ready = s_data_rx_ready_fifo_out & ~cfg_rx_blocked;
assign s_data_rx_valid_fifo_in = s_data_rx_valid & ~cfg_rx_blocked;

/* disable rx channel if end of ethernet frame was received */
/* set register bit "rx_blocked" in ETH_RX_CFG register */
assign cfg_rx_set_blocked = s_data_rx_ready & s_data_rx_valid_fifo_in & s_data_rx[8];
assign cfg_rx_set_eof = cfg_rx_set_blocked;

/* tx fifos */
io_generic_fifo #(
    .DATA_WIDTH(8),
    .BUFFER_DEPTH(RX_FIFO_BUFFER_DEPTH)
) u_fifo_rx (
    .clk_i   ( sys_clk_i       ),
    .rstn_i  ( rstn_i          ),
    .clr_i   ( 1'b0            ),

    .elements_o (cfg_rx_fifo_elements),

    .data_o  ( s_data_rx_o       ),
    .valid_o ( data_rx_valid_o ),
    .ready_i ( data_rx_ready_i ),

    .valid_i   ( s_data_rx_valid_fifo_in   ),
    .data_i  ( s_data_rx[7:0]  ),
    .ready_o ( s_data_rx_ready_fifo_out )
);



endmodule

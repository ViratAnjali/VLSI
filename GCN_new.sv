module GCN
// Parameter definitions for configuration
#(parameter FEATURE_COLS = 96,
    parameter WEIGHT_ROWS = 96,
    parameter FEATURE_ROWS = 6,
    parameter WEIGHT_COLS = 3,
    parameter FEATURE_WIDTH = 5,  // Width of each feature in bits
    parameter WEIGHT_WIDTH = 5,   // Width of each weight in bits
    parameter DOT_PROD_WIDTH = 16,  // Width for dot product operations
    parameter ADDRESS_WIDTH = 13,
    parameter COUNTER_WEIGHT_WIDTH = $clog2(WEIGHT_COLS), // Counter width for weight columns
    parameter COUNTER_FEATURE_WIDTH = $clog2(FEATURE_ROWS),// Counter width for feature rows
    parameter NUM_OF_NODES = 6, // Number of nodes in the graph		
    parameter COO_NUM_OF_COLS = 6,	// Number of columns in COO format	
    parameter COO_NUM_OF_ROWS = 2,	// Number of columns in COO format	
    parameter COO_BW = $clog2(COO_NUM_OF_COLS),// Bit-width for COO columns
    parameter MAX_ADDRESS_WIDTH = 2,  // Maximum address width
    parameter HALF_CLOCK_CYCLE = 5 // Half clock cycle for timing
)
 // Input and output ports
(
	input logic clk,
	input logic reset,
	input logic start,
	input logic [WEIGHT_WIDTH-1:0] data_in [0:WEIGHT_ROWS-1],// Input data for weights
	input logic [COO_BW-1:0] coo_in [0:COO_NUM_OF_ROWS-1], // Input COO format data
	output logic [COO_BW-1:0] coo_address, // COO address for output
	output logic [ADDRESS_WIDTH-1:0] read_address,// Read address for memory
	output logic [MAX_ADDRESS_WIDTH-1:0] max_addi_answer [0:FEATURE_ROWS-1], // Max index answer for each feature
	output logic enable_read, // Enable read for memory
	output logic done // Signal when done processing
);
// Internal signals and logic for module
logic done_trans;
logic [15:0] fm_wm_row_out [0:FEATURE_ROWS-1];
logic done_comb;
logic [COO_BW-1:0] read_row;
logic [DOT_PROD_WIDTH-1:0] adj_fm_wm_row [0:WEIGHT_COLS-1];
logic done_arg, donet;
// Instantiation of the transformation block module
transformation_top_block transtop (
	.start(start),
	.clk(clk),
	.reset(reset),
	.input_data(data_in),
	.enable_read(enable_read),
	.done_trans(donet),
	.done(done_trans),
	.read_address(read_address),
	.fm_wm_row_out(fm_wm_row_out));
 // Instantiation of the Graph Neighbor Processor module
Graph_Neighbor_Processor comtop (
	.clk(clk),
	.reset(reset),
	.fm_wm_row(fm_wm_row_out),
	.done_trans(done_trans),
	.coo_in(coo_in),
	.coo_addr(coo_address),
	.comb_done(done_comb),
    .read_row(read_row),
	.adj_fm_wm_row(adj_fm_wm_row)
);
// Instantiation of the Node Classifier module
Node_Classifier argtop (
	.clk(clk),
	.rst(reset),
	.done_comb(done_comb),
	.adj_fm_wm(adj_fm_wm_row),
	.max_addi_ans(max_addi_answer),
	.done_arg(done_arg),
        .read_row(read_row)
);
// Done signal is a combination of the argument processing and transformation done signals

assign done = done_arg & donet;

endmodule
// Additional module for FSM (Finite State Machine) control for the transformation

module Transformation_FSM 
#(parameter FEATURE_ROWS = 6,
    parameter WEIGHT_COLS = 3,
    parameter COUNTER_WEIGHT_WIDTH = $clog2(WEIGHT_COLS),
    parameter COUNTER_FEATURE_WIDTH = $clog2(FEATURE_ROWS))
(
// Inputs and outputs for FSM functionality
    input logic clk,
    input logic reset,
    output logic [12:0] weight_count,
    output logic [12:0] feature_count,
    input logic start,
    output logic enable_read,
    output logic enable_scratch_pad,
    output logic enable_weight_counter,
    output logic enable_feature_counter,
    output logic read_feature_or_weight, 
    output logic done
);
// FSM logic and control

    typedef enum logic [2:0] {
        START,
        READ_WEIGHT_DATA,
        INCREMENT_WEIGHT_COUNTER,
        READ_FEATURE_DATA,
        INCREMENT_FEATURE_COUNTER,
        DONE
    } state_t;

    state_t current_state, next_state;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= START;
        end
        else begin
            current_state <= next_state;
        end
    end

    always_comb begin
        case (current_state)
            START: begin
                enable_read = 1'b0;
                enable_scratch_pad = 1'b0;
                enable_weight_counter = 1'b0;
                enable_feature_counter = 1'b0;
                read_feature_or_weight = 1'b0; 
                done = 1'b0;
                weight_count = {COUNTER_WEIGHT_WIDTH{1'b0}};
                feature_count = {COUNTER_FEATURE_WIDTH{1'b0}};
                next_state = start ? READ_WEIGHT_DATA : START;
            end

            READ_WEIGHT_DATA: begin
                enable_read = 1'b1;
                enable_scratch_pad = 1'b1;
                enable_weight_counter = 1'b0;
                enable_feature_counter = 1'b0;
                read_feature_or_weight = 1'b0; 
                done = 1'b0;
                next_state = (weight_count == WEIGHT_COLS) ? DONE : READ_FEATURE_DATA;
            end

            INCREMENT_WEIGHT_COUNTER: begin
                enable_read = 1'b0;
                enable_scratch_pad = 1'b0;
                enable_weight_counter = 1'b1;
                enable_feature_counter = 1'b0;
                read_feature_or_weight = 1'b0; 
                done = 1'b0;
                feature_count = {COUNTER_FEATURE_WIDTH{1'b0}};
                weight_count = weight_count + 1;
                next_state = READ_WEIGHT_DATA;
            end

            READ_FEATURE_DATA: begin
                enable_read = 1'b1;
                enable_scratch_pad = 1'b0;
                enable_weight_counter = 1'b0;
                enable_feature_counter = 1'b0;
                read_feature_or_weight = 1'b1; 
                done = 1'b0;
                next_state = INCREMENT_FEATURE_COUNTER;
            end

            INCREMENT_FEATURE_COUNTER: begin
                enable_read = 1'b0;
                enable_scratch_pad = 1'b0;
                enable_weight_counter = 1'b0;
                enable_feature_counter = 1'b1;
                read_feature_or_weight = 1'b1; 
                done = 1'b0;
                if (feature_count == FEATURE_ROWS - 1) begin
                    next_state = INCREMENT_WEIGHT_COUNTER;
                end else begin
                    next_state = READ_FEATURE_DATA;
                end
                feature_count = feature_count + 1;
            end

            DONE: begin
                enable_read = 1'b0;
                enable_scratch_pad = 1'b0;
                enable_weight_counter = 1'b0;
                enable_feature_counter = 1'b0;
                read_feature_or_weight = 1'b0; 
                done = 1'b1;
                next_state = DONE;
            end

            default: begin
                enable_read = 1'b0;
                enable_scratch_pad = 1'b0;
                enable_weight_counter = 1'b0;
                enable_feature_counter = 1'b0;
                read_feature_or_weight = 1'b0; 
                done = 1'b0;
                next_state = START;
            end
        endcase
    end
endmodule
/*
Feature_Weight_Address_Generator Module
This module generates read addresses for feature and weight data. The address is determined
based on whether we are reading feature data or weight data and if read operations are enabled
*/
module Feature_Weight_Address_Generator
#(parameter FEATURE_ROWS = 6,
    parameter WEIGHT_COLS = 3,
    parameter COUNTER_WEIGHT_WIDTH = $clog2(WEIGHT_COLS),
    parameter COUNTER_FEATURE_WIDTH = $clog2(FEATURE_ROWS))
(
    input logic clk,
    input logic reset,
    input logic enable_read,
    input logic enable_weight_counter,
    input logic enable_feature_counter,
    input logic read_feature_or_weight,
    input logic [12:0] read_address_w, 
    input logic [12:0] read_address_f,
    output logic [12:0] read_address
);
// Address generation logic
    always_comb begin
        if(reset) begin
            read_address = 10'b0000_0000_00;
        end
        else if(~read_feature_or_weight & enable_read) begin
            read_address = read_address_w;
        end
        else if(read_feature_or_weight & enable_read) begin
            read_address = read_address_f + 13'h200;
        end
        else begin
            read_address = 10'b0000_0000_00;
        end
    end
endmodule
/*
Dot_Product_Engine Module
This module performs the dot product between feature and weight data. It computes partial products,
segments them into 8 groups, sums the results for each group, and produces the final dot product output.
*/


module Dot_Product_Engine
#(parameter FEATURE_COLS = 96,
    parameter WEIGHT_ROWS = 96,
    parameter FEATURE_ROWS = 6,
    parameter WEIGHT_COLS = 3,
    parameter FEATURE_WIDTH = 5,
    parameter WEIGHT_WIDTH = 5,
    parameter DOT_PROD_WIDTH = 16)
(
    input logic clk,
    input logic reset,
    input logic enable_scrth,
    input logic enable_read,
    input logic [FEATURE_WIDTH-1:0] data_in [0:FEATURE_COLS-1],
    output logic [15:0] prod,
    input logic [FEATURE_WIDTH-1:0] scrth_pad [0:FEATURE_COLS-1],
    output logic enable_write
);

    logic compute_enable;
    logic [DOT_PROD_WIDTH-1:0] partial_products [0:WEIGHT_ROWS-1];// Store partial product results
    logic [DOT_PROD_WIDTH-1:0] segment_sums [0:7];// Sum partial products into 8 segments

// Compute dot product and sum the results in segments
    always @(posedge clk or posedge reset) begin
    if (compute_enable) begin
    for (int i = 0; i < WEIGHT_ROWS; i++) begin
                partial_products[i] <= data_in[i] * scrth_pad[i]; // Element-wise multiplication
    end
           // Segmenting the partial products and summing them

            segment_sums[0] <= partial_products[0] + partial_products[1] + partial_products[2] + partial_products[3] + 
                              partial_products[4] + partial_products[5] + partial_products[6] + partial_products[7] + 
                              partial_products[8] + partial_products[9] + partial_products[10] + partial_products[11];
            
            segment_sums[1] <= partial_products[12] + partial_products[13] + partial_products[14] + partial_products[15] + 
                              partial_products[16] + partial_products[17] + partial_products[18] + partial_products[19] + 
                              partial_products[20] + partial_products[21] + partial_products[22] + partial_products[23];
            
            segment_sums[2] <= partial_products[24] + partial_products[25] + partial_products[26] + partial_products[27] + 
                              partial_products[28] + partial_products[29] + partial_products[30] + partial_products[31] + 
                              partial_products[32] + partial_products[33] + partial_products[34] + partial_products[35];

            segment_sums[3] <= partial_products[36] + partial_products[37] + partial_products[38] + partial_products[39] + 
                              partial_products[40] + partial_products[41] + partial_products[42] + partial_products[43] + 
                              partial_products[44] + partial_products[45] + partial_products[46] + partial_products[47];

            segment_sums[4] <= partial_products[48] + partial_products[49] + partial_products[50] + partial_products[51] + 
                              partial_products[52] + partial_products[53] + partial_products[54] + partial_products[55] + 
                              partial_products[56] + partial_products[57] + partial_products[58] + partial_products[59];

            segment_sums[5] <= partial_products[60] + partial_products[61] + partial_products[62] + partial_products[63] + 
                              partial_products[64] + partial_products[65] + partial_products[66] + partial_products[67] + 
                              partial_products[68] + partial_products[69] + partial_products[70] + partial_products[71];

            segment_sums[6] <= partial_products[72] + partial_products[73] + partial_products[74] + partial_products[75] + 
                              partial_products[76] + partial_products[77] + partial_products[78] + partial_products[79] + 
                              partial_products[80] + partial_products[81] + partial_products[82] + partial_products[83];

            segment_sums[7] <= partial_products[84] + partial_products[85] + partial_products[86] + partial_products[87] + 
                              partial_products[88] + partial_products[89] + partial_products[90] + partial_products[91] + 
                              partial_products[92] + partial_products[93] + partial_products[94] + partial_products[95];
           
      // Final dot product computation
            prod <= segment_sums[0] + segment_sums[1] + segment_sums[2] + segment_sums[3] + 
                   segment_sums[4] + segment_sums[5] + segment_sums[6] + segment_sums[7];
            
            enable_write <= 1'b1;
        end
    end
    // Control computation enable signal
    assign compute_enable = ~enable_scrth && enable_read;
endmodule
/*
Enhanced_Memory_Unit Module
This module handles memory operations for feature-weight data. It supports writing data into memory
and handling state transitions for the storage and retrieval process.
*/


module Enhanced_Memory_Unit
#(parameter FEATURE_ROWS = 6,
    parameter WEIGHT_COLS = 3,
    parameter DOT_PROD_WIDTH = 16,
    parameter ADDRESS_WIDTH = 13,
    parameter WEIGHT_WIDTH = $clog2(WEIGHT_COLS),
    parameter FEATURE_WIDTH = $clog2(FEATURE_ROWS)
)
(
    input logic clk,
    input logic rst,
    input logic [12:0] write_row,
    input logic [12:0] write_col,
    input logic wr_en,
    input logic [DOT_PROD_WIDTH - 1:0] fm_wm_in,
    output logic done,
    output logic [DOT_PROD_WIDTH - 1:0] fm_wm_row_out [0:FEATURE_ROWS-1] // Output feature-weight data
);

    logic transition_state;  // Holds current transition state
    logic delayed_transition;// Holds delayed transition state
    logic transition_complete;// Flag for transition completion
    logic [2:0] primary_count, secondary_count; // Counters for state transitions
    logic [DOT_PROD_WIDTH - 1:0] mem [0:FEATURE_ROWS-1];  // Memory array for storing data
    
    // Internal signals for transition conditions
    logic in_trans_cond;
    logic out_trans_cond;

    // Memory initialization and writing
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int j = 0; j < FEATURE_ROWS; j = j + 1) begin
                mem[j] <= {DOT_PROD_WIDTH{1'b0}};
            end
        end 
        else if (wr_en && write_row > 0 && write_row <= FEATURE_ROWS) begin
            mem[write_row-1] <= fm_wm_in;
        end
    end

    // Transition conditions (combinational)
    assign in_trans_cond = (write_row < FEATURE_ROWS && wr_en);
    assign out_trans_cond = (write_row == FEATURE_ROWS && wr_en);
    assign transition_complete = (secondary_count == 3'd7);

    // State transition logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            transition_state <= 1'b0;
            secondary_count <= 3'b0;
        end
        else begin
            if (transition_complete) begin
                transition_state <= 1'b0;
                secondary_count <= 3'b0;
            end
            else if (out_trans_cond) begin
                transition_state <= 1'b1;
                secondary_count <= 3'b0;
            end
            else if (in_trans_cond) begin
                secondary_count <= secondary_count + 1;
            end
        end
    end

    // Delayed signal generation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            delayed_transition <= 1'b0;
            primary_count <= 3'b0;
        end
        else if (primary_count == 3'd6) begin
            delayed_transition <= transition_state;
            primary_count <= 3'b0;
        end
        else begin
            primary_count <= primary_count + 1;
        end
    end

    assign done = ~delayed_transition & transition_state;
    assign fm_wm_row_out = mem;
endmodule
/*
Scratch_Pad Module
This module simulates a scratchpad memory used for temporary storage of weight columns. It supports
writing data into memory when the write enable signal is active.
*/

module Scratch_Pad 
  #(parameter WEIGHT_ROWS = 96,
    parameter WEIGHT_WIDTH = 5
)
(
  input logic clk,
  input logic reset,
  input logic write_enable,
  input wire [WEIGHT_WIDTH-1:0] weight_col_in [0:WEIGHT_ROWS-1],
  output logic [WEIGHT_WIDTH-1:0] weight_col_out [0:WEIGHT_ROWS-1]
);

 logic [WEIGHT_WIDTH-1:0] memory [0:WEIGHT_ROWS-1];

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin 
       for (int i = 0; i < WEIGHT_ROWS; i = i + 1) begin
          memory[i] <= '0;
       end
    end
    else if (write_enable) begin
      memory <= weight_col_in;
    end
  end

  assign weight_col_out = memory;
endmodule
/*
transformation_top_block Module
This top-level block orchestrates the transformation operations. It coordinates the
submodules like the FSM, address generator, and scratchpad memory to perform the feature
and weight matrix transformations for the GCN.
*/


module transformation_top_block
#(parameter FEATURE_ROWS = 6,
    parameter WEIGHT_COLS = 3,
    parameter FEATURE_COLS = 96,
    parameter WEIGHT_ROWS = 96,
    parameter FEATURE_WIDTH = 5,
    parameter WEIGHT_WIDTH = 5,
    parameter COUNTER_WEIGHT_WIDTH = $clog2(WEIGHT_COLS),
    parameter COUNTER_FEATURE_WIDTH = $clog2(FEATURE_ROWS))
(
	input logic start,
	input logic clk,
	input logic reset,
	input logic [WEIGHT_WIDTH-1:0] input_data [0:WEIGHT_ROWS-1],
	output logic enable_read,
	output logic done_trans,
	output logic done, 
	output logic [12:0] read_address,
	output logic [15:0] fm_wm_row_out [0:FEATURE_ROWS-1]
);

logic enable_weight_counter;
logic enable_feature_counter;
logic read_feature_or_weight;
logic enable_write;
logic scrth_pad;
logic [12:0] w_c;
logic [12:0] f_c;
logic [FEATURE_WIDTH-1:0] scrth_pad_mem [0:FEATURE_COLS-1];
logic [15:0] prod_out;
// Instantiate the Transformation FSM to control the transformation process
Transformation_FSM tfsm (
	.clk(clk), 
	.start(start),
	.reset(reset),
	.weight_count(w_c),
	.feature_count(f_c),
	.enable_read(enable_read),
	.enable_scratch_pad(scrth_pad),
	.enable_weight_counter(enable_weight_counter),
	.enable_feature_counter(enable_feature_counter),
	.read_feature_or_weight(read_feature_or_weight),
	.done(done_trans));
// Instantiate the feature and weight address generator
Feature_Weight_Address_Generator fwcr (
	.clk(clk),
	.reset(reset),
	.enable_read(enable_read),
	.enable_weight_counter(enable_weight_counter),
	.enable_feature_counter(enable_feature_counter),
	.read_feature_or_weight(read_feature_or_weight),
	.read_address_w(w_c),
	.read_address_f(f_c),
	.read_address(read_address));
 // Instantiate the Dot Product Engine for performing matrix multiplication
Dot_Product_Engine mult (
	.clk(clk),
	.reset(reset),
	.enable_read(enable_read),
	.enable_scrth(scrth_pad),
	.data_in(input_data),
	.enable_write(enable_write),
	.prod(prod_out),
	.scrth_pad(scrth_pad_mem)
);
// Instantiate the scratchpad for temporary storage of weight columns
Scratch_Pad sp (
	.clk(clk),
	.reset(reset),
	.write_enable(scrth_pad),
	.weight_col_in(input_data),
	.weight_col_out(scrth_pad_mem)
);
// Instantiate the Enhanced Memory Unit to store and process the feature-weight data
Enhanced_Memory_Unit mem (
	.clk(clk),
	.rst(reset),
	.write_row(f_c),
	.write_col(w_c),
	.wr_en(enable_write),
	.done(done),
	.fm_wm_in(prod_out),
	.fm_wm_row_out(fm_wm_row_out)
);
endmodule

/*
Graph_Neighbor_Processor Module
This module processes the graph's neighbor data and updates the adjacency matrix. 
It performs the computation of feature-weight matrix multiplications and matrix updates.
*/
module Graph_Neighbor_Processor
#(parameter COO_NUM_OF_COLS = 6,
    parameter COO_NUM_OF_ROWS = 2,
    parameter COO_BW = $clog2(COO_NUM_OF_COLS),
    parameter DOT_PROD_WIDTH = 16,
    parameter WEIGHT_COL = 3,
    parameter FEATURE_ROWS = 6,
    parameter WEIGHT_COLS = 3,
    parameter FEATURE_WIDTH = 5)
(
    input logic clk,
    input logic reset,
    input logic done_trans,
    input logic [DOT_PROD_WIDTH-1:0] fm_wm_row [0:COO_NUM_OF_COLS-1],
    input logic [COO_BW-1:0] coo_in [0:COO_NUM_OF_ROWS-1],
    output logic [COO_BW-1:0] coo_addr,
    input logic [COO_BW-1:0] read_row,
    output logic [DOT_PROD_WIDTH-1:0] adj_fm_wm_row [0:WEIGHT_COLS-1],
    output logic comb_done
);
    logic [COO_BW-1:0] coo_counter, weight_counter, coo_index;
    logic [COO_BW-1:0] coo_matrix [0:COO_NUM_OF_ROWS-1][0:COO_NUM_OF_COLS-1];// Matrix for COO format
    logic coo_valid, weight_update;
    logic [DOT_PROD_WIDTH-1:0] adjacency_matrix [0:FEATURE_ROWS-1][0:WEIGHT_COLS-1];// Adjacency matrix for graph

// Reset and initialization logic for COO matrix and adjacency matrix
  always @(posedge clk or posedge reset) begin
        if(reset) begin
            comb_done <= 0;
            coo_index<={COO_BW{1'b0}}; 
            for (int i = 0; i < FEATURE_ROWS; i++) begin
                for (int j = 0; j < WEIGHT_COLS; j++) begin
                    adjacency_matrix[i][j] <= {DOT_PROD_WIDTH{1'b0}};
                end
            end
            
            for(int i=0; i<COO_NUM_OF_COLS; i++) begin
                coo_matrix[0][i] <= {COO_BW{1'b0}};
                coo_matrix[1][i] <= {COO_BW{1'b0}};
            end
        end
        else if(done_trans) begin
            comb_done <= (weight_counter == WEIGHT_COLS-1) ? 1'b1 : 1'b0;
            // Update adjacency matrix with results from feature-weight multiplication
            adjacency_matrix[coo_matrix[0][coo_index]][weight_counter] <= 
                adjacency_matrix[coo_matrix[0][coo_index]][weight_counter] + 
                fm_wm_row[5 - coo_matrix[1][coo_index]]; 
                
            adjacency_matrix[coo_matrix[1][coo_index]][weight_counter] <= 
                adjacency_matrix[coo_matrix[1][coo_index]][weight_counter] + 
                fm_wm_row[5 - coo_matrix[0][coo_index]];  
                
            coo_index <= (~weight_update) ? coo_index + 1 : {COO_BW{1'b0}};
        end
        else begin
            coo_matrix[0][coo_addr] <= (coo_valid) ? coo_in[0]-1 : {COO_BW{1'b0}};
            coo_matrix[1][coo_addr] <= (coo_valid) ? coo_in[1]-1 : {COO_BW{1'b0}};
        end
    end
// Control the COO address and coo_counter logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            weight_counter <= 0;
            coo_addr <= {COO_BW{1'b0}};
            coo_counter <= {COO_BW{1'b0}};
        end
        else if(done_trans && weight_update) begin
            weight_counter <= weight_counter + 1;
        end
        else if(coo_valid) begin
            coo_addr <= coo_addr + 1;
            coo_counter <= coo_counter + 1;
        end
    end
    
    assign adj_fm_wm_row = adjacency_matrix[read_row];
    assign coo_valid = (coo_counter < COO_NUM_OF_COLS) ? 1'b1 : 1'b0;
    assign weight_update = (coo_index < COO_NUM_OF_COLS) ? 1'b0 : 1'b1;
endmodule  
/*
Node_Classifier Module
This module classifies nodes in the graph based on the dot product of feature-weight data.
It selects the maximum value and classifies nodes accordingly.
*/

module Node_Classifier
#(
    parameter DOT_PROD_WIDTH = 16,
    parameter WEIGHT_COLS = 3,
    parameter FEATURE_ROWS = 6,
    parameter MAX_ADDRESS_WIDTH = $clog2(WEIGHT_COLS)
)
(
    input logic clk,
    input logic rst,
    input logic done_comb,
    input logic [DOT_PROD_WIDTH-1:0] adj_fm_wm[WEIGHT_COLS-1:0], // Adjacency feature-weight matrix
    output logic [$clog2(FEATURE_ROWS)-1:0] read_row,
    output logic [MAX_ADDRESS_WIDTH-1:0] max_addi_ans[0:FEATURE_ROWS-1], // Max address answer for each node
    output logic done_arg
);

// Internal signals
logic [MAX_ADDRESS_WIDTH-1:0] max_index; // Index for maximum value in adjacency matrix
integer i;

// Find max index logic for classification
always_comb begin
    max_index = 0;
    for (i = 1; i < WEIGHT_COLS; i = i + 1) begin
        if (adj_fm_wm[i] > adj_fm_wm[max_index]) begin
            max_index = i;
        end
    end
end

// Sequential logic to process node classification
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        read_row <= 0;
        done_arg <= 0;
        for (int j = 0; j < FEATURE_ROWS; j++) begin
            max_addi_ans[j] <= 0; // Reset classification results
        end
    end
    else if (done_comb && !done_arg) begin
        if (read_row < FEATURE_ROWS) begin
            max_addi_ans[read_row] <= (WEIGHT_COLS-1) - max_index; // Store max index address
            read_row <= read_row + 1; // Move to the next row
        end
        done_arg <= (read_row == FEATURE_ROWS-1);// Set done signal when all rows are processed
    end
end

endmodule

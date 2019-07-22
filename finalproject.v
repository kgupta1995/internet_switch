module portin (input clock,reset_n,frame_n,valid_n,di,output reg[3:0]addr,output reg[31:0]payload,output vld,input clear);

reg [4:0]cnt;
reg vld_reg;
assign vld = vld_reg & !clear;
 
always @(posedge clock, negedge reset_n)
begin
if (!reset_n) begin
	cnt <= 0; 
	vld_reg <= 0;
end  
else if (valid_n && !frame_n)begin
	addr[cnt] <=di;

	if (cnt == 3) 
		cnt <= 0;
	else cnt <= cnt + 1;
end

else if (!frame_n && !valid_n) begin
	payload [cnt] <=di;
	cnt <= cnt+1;
	
end
else if (frame_n && !valid_n) begin
	payload [cnt]<= di;
	cnt <=0;
	vld_reg <=1;
end
else if (clear) begin
	vld_reg <=0;
end
end
endmodule

module multiplexer (sel,data_out,data_in);
input [31:0]data_in[7:0];
output reg [31:0] data_out;
input  [2:0]sel;

always @(*)
	begin 
        case (sel)
3'b000 : data_out = data_in[0];
3'b001 : data_out = data_in[1];
3'b010 : data_out = data_in[2];
3'b011 : data_out = data_in[3];
3'b100 : data_out = data_in[4];
3'b101 : data_out = data_in[5];
3'b110 : data_out = data_in[6];
3'b111 : data_out = data_in[7];
          endcase
         end 
	
endmodule




module portout (input clock, reset_n, input [31:0] din, input vld,output reg frame_n,valid_n,dout, output reg pop);

reg [4:0]cnt;
reg [31:0] payload_in;
reg [1:0]state ;


//Always block for valid_n
always @ (posedge clock, negedge reset_n)
begin
	if (!reset_n) 
	begin
		cnt<=0;
		dout <=0;
		valid_n <=1;
		frame_n <=1;
		pop <= 0; 
		payload_in <= 0;
		state <=2'b00;
	end
	else if(state == 2'b00) 
	begin //{
		pop <= 0; 
		frame_n <=1;
		valid_n <=1;
		dout<= 0;
		cnt <= 0;

		if (vld == 1)         
		begin // {                  
			state <= 2'b01;
			pop <= 0;  $display("The value of pop is: Simple string",pop);
			
		end //}
		else 
			state <= 2'b00;
			pop <= 0;
			 
	
	
	end //}

	else if (state == 2'b01)
	begin
		pop <= 1;
	    state <= 2'b10;
	    payload_in <= din;

	end
	
	else if(state == 2'b10)
	begin
		pop <= 0; 
		dout <= payload_in[cnt];
		cnt <= cnt +1 ;
		valid_n <=0;
		frame_n <= 0;
	
		if ( cnt > 'd30)
		begin
			state <= 2'b00;
			frame_n <= 1;
		end
	end
	else 
	begin  
		state <= 2'b10;
		pop <= 1; 
	end
end
endmodule


module router (
input clock, reset_n,
input [7:0] frame_n,
input [7:0] valid_n,
input [7:0] di, output [7:0]dout,
output [7:0] valido_n, [7:0] frameo_n);

// interconnect wires that you will need  , try to make the names meaningful 
wire [2:0] sel [7:0];
wire [3:0] addr_from_input [7:0];
wire [31:0] payload_from_input [7:0];
wire [31:0] payload_from_fifo [7:0];
wire [31:0] payload_from_mux [7:0];
wire [7:0] fifo_empty ;
wire [7:0] vld_from_input ;
wire [7:0] req_to_arb[7:0] ;
wire [7:0] request_from_fifo ;
wire [7:0] clear ;
wire [7:0] grant [7:0];

// Let's use generate statements (will discuss this in class next week) to instantiate the 8-slices
genvar i;
generate 
for (i=0;i<8;i=i+1)
	 begin :inst
       portin portin (.clock(clock),
               .reset_n(reset_n),
               .frame_n(frame_n[i]), 
               .valid_n(valid_n[i]), 
               .di(di[i]),
               .addr(addr_from_input[i]),
               .payload(payload_from_input[i]),
               .vld(vld_from_input[i]), 
               .clear(clear[i]));
  //portin portin (.clock(clock),.reset_n(reset_n),.frame_n(frame_n[i]), .valid_n(valid_n[i]), .di(di[i]),.addr(addr_from_input[i]),.payload(payload_from_input[i]),.vld(vld_from_input[i]), .clear(clear[i]) );             	

	       DW_arb_rr #(8,1,2) arb(.clk(clock),
                       .rst_n(reset_n),
                       .init_n(1'b1),
                       .enable(1'b1),
                       .request(req_to_arb[i]),
                       .mask(8'b0000_0000),
                       .granted(),
                       .grant(grant[i]),
                       .grant_index(sel[i])) ; //a

		DW_fifo_s1_df #(32, 8, 0, 0) fifo (.clk(clock), 
                                   .rst_n(reset_n), 
                                   .push_req_n(!grant[i]), 
                                   .pop_req_n(!request_from_fifo[i]),
                                   .diag_n(1'b1), 
                                   .ae_level(3'h0), 
                                   .af_thresh(3'h0), 
                                   .data_in(payload_from_mux[i]), 
                                   .empty(fifo_empty[i]),
                                   .almost_empty(), 
                                   .half_full(),      
                                   .almost_full(), 
                                   .full(), 
                                   .error(), 
                                   .data_out(payload_from_fifo[i]) );

        multiplexer multiplexer (.data_in(payload_from_input),
                                 .sel(sel[i]), //a
                                 .data_out(payload_from_mux[i]));

		portout portout (.clock(clock), 
                 		.reset_n(reset_n) , 
                 		.din(payload_from_fifo[i]), 
                 		.vld(!fifo_empty[i]),
                 		.frame_n(frameo_n[i]),
                 		.valid_n(valido_n[i]),
                		.dout(dout[i]), 
                 		.pop( request_from_fifo[i]) );

assign req_to_arb[i] = vld_from_input &

{addr_from_input[7]==i,addr_from_input[6]==i, addr_from_input[5]==i, addr_from_input[4]==i,addr_from_input[3]==i, addr_from_input[2]==i, addr_from_input[1]==i, addr_from_input[0]==i};

end
endgenerate


assign clear[7] = grant[0][7]|grant[1][7]|grant[2][7]|grant[3][7]|grant[4][7]|grant[5][7]|grant[6][7]|grant[7][7]; 
assign clear[6] = grant[0][6]|grant[1][6]|grant[2][6]|grant[3][6]|grant[4][6]|grant[5][6]|grant[6][6]|grant[7][6];
assign clear[5] = grant[0][5]|grant[1][5]|grant[2][5]|grant[3][5]|grant[4][5]|grant[5][5]|grant[6][5]|grant[7][5];
assign clear[4] = grant[0][4]|grant[1][4]|grant[2][4]|grant[3][4]|grant[4][4]|grant[5][4]|grant[6][4]|grant[7][4];
assign clear[3] = grant[0][3]|grant[1][3]|grant[2][3]|grant[3][3]|grant[4][3]|grant[5][3]|grant[6][3]|grant[7][3];
assign clear[2] = grant[0][2]|grant[1][2]|grant[2][2]|grant[3][2]|grant[4][2]|grant[5][2]|grant[6][2]|grant[7][2];
assign clear[1] = grant[0][1]|grant[1][1]|grant[2][1]|grant[3][1]|grant[4][1]|grant[5][1]|grant[6][1]|grant[7][1];
assign clear[0] = grant[0][0]|grant[1][0]|grant[2][0]|grant[3][0]|grant[4][0]|grant[5][0]|grant[6][0]|grant[7][0];


endmodule



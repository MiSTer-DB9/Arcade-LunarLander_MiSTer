module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output [11:0] VIDEO_ARX,
	output [11:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler

	// Use framebuffer from DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of 16 bytes.
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

		// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,


	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	
	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	output	USER_OSD,
	output	[1:0] USER_MODE,
	input	[7:0] USER_IN,
	output	[7:0] USER_OUT
);

assign VGA_F1    = 0;
assign VGA_SCALER= 0;

wire         CLK_JOY = CLK_50M;         //Assign clock between 40-50Mhz
wire   [2:0] JOY_FLAG  = {status[30],status[31],status[29]}; //Assign 3 bits of status (31:29) o (63:61)
wire         JOY_CLK, JOY_LOAD, JOY_SPLIT, JOY_MDSEL;
wire   [5:0] JOY_MDIN  = JOY_FLAG[2] ? {USER_IN[6],USER_IN[3],USER_IN[5],USER_IN[7],USER_IN[1],USER_IN[2]} : '1;
wire         JOY_DATA  = JOY_FLAG[1] ? USER_IN[5] : '1;
assign       USER_OUT  = JOY_FLAG[2] ? {3'b111,JOY_SPLIT,3'b111,JOY_MDSEL} : JOY_FLAG[1] ? {6'b111111,JOY_CLK,JOY_LOAD} : '1;
assign       USER_MODE = JOY_FLAG[2:1] ;
assign       USER_OSD  = joydb_1[10] & joydb_1[6];

assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;


wire [1:0] ar = status[15:14];
assign VIDEO_ARX =  (!ar) ? ( 8'd4) : (ar - 1'd1);
assign VIDEO_ARY =  (!ar) ? ( 8'd3) : 12'd0;


`include "build_id.v" 
localparam CONF_STR = {
	"A.LLANDER;;",
	"H0OEF,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",
	"OUV,UserIO Joystick,Off,DB9MD,DB15 ;",
	"OT,UserIO Players, 1 Player,2 Players;",
	"-;",
	"OD,Thruster,Analog Stick,D-Pad;",
	"-;",
	"O7,Test,Off,On;",
	"O89,Language,English,Spanish,French,German;",
	"OAC,Fuel,450,600,750,900,1100,1300,1550,1800;",
	"-;",
	"R0,Reset;",
	"J1,Start,Select,Coin,Abort,Turn Right,Turn Left;",	
    "jn,Start,Select,X,A,L,R;",
	"V,v",`BUILD_DATE
};
// 00010000
// on is 0
//wire [7:0] m_dip = {~status[12:11],1'b1,~status[10],~status[9:8],1'b0,1'b0};
wire [7:0] m_dip = {1'b0,1'b0,status[8],status[9],~status[10],1'b1,status[11],status[12]};
//wire [7:0] m_dip = 8'b00010000;

////////////////////   CLOCKS   ///////////////////

wire clk_6, clk_25,clk_50;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_50),	
	.outclk_1(clk_25),	
	.outclk_2(clk_6),	
	.locked(pll_locked)
);


///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [15:0] joy_0_USB, joy_1_USB;
wire [15:0] joy = joy_0 | joy_1;
wire [21:0] gamma_bus;

// TL TR AB CO SE S1 U D L R 
wire [31:0] joy_0 = joydb_1ena ? {joydb_1[7],joydb_1[8],joydb_1[9], joydb_1[11]|(joydb_1[10]&joydb_1[5]), joydb_1[4],joydb_1[10],joydb_1[3:0]} : joy_0_USB;
wire [31:0] joy_1 = joydb_2ena ? {joydb_2[7],joydb_2[8],joydb_2[9], joydb_2[11]|(joydb_2[10]&joydb_2[5]), joydb_2[4],joydb_2[10],joydb_2[3:0]} : joydb_1ena ? joy_0_USB : joy_1_USB;

wire [15:0] joydb_1 = JOY_FLAG[2] ? JOYDB9MD_1 : JOY_FLAG[1] ? JOYDB15_1 : '0;
wire [15:0] joydb_2 = JOY_FLAG[2] ? JOYDB9MD_2 : JOY_FLAG[1] ? JOYDB15_2 : '0;
wire        joydb_1ena = |JOY_FLAG[2:1]              ;
wire        joydb_2ena = |JOY_FLAG[2:1] & JOY_FLAG[0];

//----BA 9876543210
//----MS ZYXCBAUDLR
reg [15:0] JOYDB9MD_1,JOYDB9MD_2;
joy_db9md joy_db9md
(
  .clk       ( CLK_JOY    ), //40-50MHz
  .joy_split ( JOY_SPLIT  ),
  .joy_mdsel ( JOY_MDSEL  ),
  .joy_in    ( JOY_MDIN   ),
  .joystick1 ( JOYDB9MD_1 ),
  .joystick2 ( JOYDB9MD_2 )	  
);

//----BA 9876543210
//----LS FEDCBAUDLR
reg [15:0] JOYDB15_1,JOYDB15_2;
joy_db15 joy_db15
(
  .clk       ( CLK_JOY   ), //48MHz
  .JOY_CLK   ( JOY_CLK   ),
  .JOY_DATA  ( JOY_DATA  ),
  .JOY_LOAD  ( JOY_LOAD  ),
  .joystick1 ( JOYDB15_1 ),
  .joystick2 ( JOYDB15_2 )	  
);

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_25),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),


	.buttons(buttons),
	.status(status),
	.status_menumask(direct_video),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),

	.joystick_0(joy_0_USB),
	.joystick_1(joy_1_USB),
	.joystick_analog_0(analog_joy_0)
	.joy_raw(joydb_1[5:0] | joydb_2[5:0])
);


wire hblank, vblank;
wire ohblank, ovblank;

wire hs, vs;
wire ohs, ovs;
wire [2:0] r,g,b;
wire [7:0] outr,outg,outb;



reg ce_pix;
always @(posedge clk_50) begin
       ce_pix <= !ce_pix;
end
reg [3:0] r2;
reg [3:0] g2;
reg [3:0] b2;

always @(posedge clk_50) begin
    r2<=outr[7:5];
	 g2<=outg[7:5];
    b2<=outb[7:5];
end

arcade_video #(640,12) arcade_video
(
        .*,

        .clk_video(clk_50),

        .RGB_in({r2,g2,b2}),

        .HBlank(ohblank),
        .VBlank(ovblank),
        .HSync(ohs),
        .VSync(ovs),

        .forced_scandoubler(0),
        .fx(0)
);



ovo #(.COLS(1), .LINES(1), .RGB(24'hFF00FF)) diff (
	.i_r({r,r,r[2:1]}),
	.i_g({g,g,g[2:1]}),
	.i_b({b,b,b[2:1]}),
	.i_hs(~hs),
	.i_vs(~vs),
	.i_de(vgade),
	.i_hblank(hblank),
	.i_vblank(vblank),
	.i_en(ce_pix),
	.i_clk(clk_50),

	.o_r(outr),
	.o_g(outg),
	.o_b(outb),
	.o_hs(ohs),
	.o_vs(ovs),
	.o_de(ode),
	.o_hblank(ohblank),
	.o_vblank(ovblank),

	.ena(diff_count > 0),

	.in0(difficulty),
	.in1(),
);

wire lamp2, lamp3, lamp4, lamp5;

wire [1:0] difficulty;

always_comb begin
	if(lamp5)
		difficulty = 2'd3;
	else if(lamp4)
		difficulty = 2'd2;
	else if(lamp3)
		difficulty = 2'd1;
	else
		difficulty = 2'd0;
end

int diff_count = 0;
always @(posedge CLK_50M) begin
	if (diff_count > 0)
		diff_count <= diff_count - 1;
	
	if (~in_select)
		diff_count <= 'd500_000_000; // 10 seconds
end


wire reset = (RESET | status[0] | buttons[1] | ioctl_download);
wire [7:0] audio;
assign AUDIO_L = {audio, audio};
assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 0;
wire vgade;
wire [15:0] analog_joy_0;

wire signed [7:0] signedjoy = analog_joy_0[15:8];
wire signed [7:0] signedturn = analog_joy_0[7:0];
wire [8:0] us_joy = 9'sd255 - (signedjoy + 9'sd128);


// According to mame, because of the way the DAC worked for the thrust lever,
// it was unlikely that the board ever expected to get 0xFF, so we limit to 0xFE.
wire [8:0] us_joy_mod = us_joy > 9'd254 ? 9'd254 : us_joy;

reg [7:0] dpad_thrust = 0;

// 1 second = 50,000,000 cycles (duh)
// If we want to go from zero to full throttle in 1 second we tick every
// 196,850 cycles.
always @(posedge CLK_50M) begin :thrust_count
	int thrust_count;
	thrust_count <= thrust_count + 1'd1;

	if (thrust_count == 'd196_850) begin
		thrust_count <= 0;
		if ((joy[2]) && dpad_thrust > 0)
			dpad_thrust <= dpad_thrust - 1'd1;

		if ((joy[3]) && dpad_thrust < 'd254)
			dpad_thrust <= dpad_thrust + 1'd1;
	end
end

wire joy_turn_l = (signedturn < -8'sd64);
wire joy_turn_r = (signedturn > 8'sd64);

//4     5      6    7     8          9
//Start,Select,Coin,Abort,Turn Right,Turn Left

wire in_select = ~(joy[5] );
wire in_start  = ~(joy[4] );
wire in_turn_l = ~(joy[9] | joy[1] );
wire in_turn_r = ~(joy[8] | joy[0] );
wire in_coin   = ~(joy[6] );
wire in_abort  = ~(joy[7] );

wire [7:0] in_thrust = status[13] ? dpad_thrust : us_joy_mod;

wire is_starting;

LLANDER_TOP LLANDER_TOP
(
	.ROT_LEFT_L(in_turn_l),
	.ROT_RIGHT_L(in_turn_r),
	.ABORT_L(in_abort),
	.GAME_SEL_L(in_select),
	.START_L(in_start),
	.COIN1_L(in_coin),
	.COIN2_L(in_coin),
	.THRUST(in_thrust),
	.DIAG_STEP_L(m_diag_step),
	.SLAM_L(m_slam),
	.SELF_TEST_L(~status[7]), 
	.START_SEL_L(is_starting),
	.LAMP2(lamp2),
	.LAMP3(lamp3),
	.LAMP4(lamp4),
	.LAMP5(lamp5),

	.AUDIO_OUT(audio),
	.dn_addr(ioctl_addr[15:0]),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr),	
	.VIDEO_R_OUT(r),
	.VIDEO_G_OUT(g),
	.VIDEO_B_OUT(b),
	.HSYNC_OUT(hs),
	.VSYNC_OUT(vs),
	.VGA_DE(vgade),
	.VID_HBLANK(hblank),
	.VID_VBLANK(vblank),
	.DIP(m_dip),
	.RESET_L (~reset),	
	.clk_6(clk_6),
	.clk_25(clk_25)
);

endmodule

// Replays the stimulus of run_tia_rd.py on tia_cx, tia_inpt, tia_rd, tia_pf (port lists: chip-2600 #27, #28).
// tia_rd is driven by independent random cx/inpt. Outputs sampled 1 ns after each posedge clk.
// Stim line (hex): rst en objs vblank cxclr pin a rcx rinpt step start right ref pf0 pf1 pf2
`timescale 1ns/1ps
module tb_tia_rd;
  reg clk=0, rst=0, en=0, cxclr=0, step=0, start=0, right=0, ref_=0;
  reg [5:0] objs=0, pin=0, rinpt=0; reg [2:0] vblank=0; reg [3:0] a=0, pf0=0; reg [14:0] rcx=0; reg [7:0] pf1=0, pf2=0;
  wire [14:0] cx; wire [5:0] inpt; wire [1:0] d_out, d_oe; wire pf;
  // objs bit order = p0 p1 m0 m1 bl pf (bit0 = p0), as ref/tia_rd.py OBJ
  tia_cx   u_cx(.clk(clk),.rst(rst),.p0(objs[0]),.p1(objs[1]),.m0(objs[2]),.m1(objs[3]),.bl(objs[4]),.pf(objs[5]),
                .vblank(vblank[0]),.en(en),.cxclr(cxclr),.cx(cx));
  tia_inpt u_in(.clk(clk),.rst(rst),.inpt_pin(pin),.vblank(vblank),.inpt(inpt));
  tia_rd   u_rd(.a(a),.cx(rcx),.inpt(rinpt),.d_out(d_out),.d_oe(d_oe));
  tia_pf   u_pf(.clk(clk),.rst(rst),.step(step),.start(start),.right(right),.ref(ref_),.pf0(pf0),.pf1(pf1),.pf2(pf2),.pf(pf));
  integer fi, fo, n, i, rc; reg [1023:0] sf, of;
  integer v_rst, v_en, v_objs, v_vb, v_clr, v_pin, v_a, v_rcx, v_rin, v_step, v_start, v_right, v_ref, v_p0, v_p1, v_p2;
  initial begin
    if (!$value$plusargs("STIM=%s", sf) || !$value$plusargs("OUT=%s", of) || !$value$plusargs("N=%d", n)) begin $display("need +STIM +OUT +N"); $finish; end;
    fi=$fopen(sf,"r"); fo=$fopen(of,"w");
    for (i=0;i<n;i=i+1) begin
      rc=$fscanf(fi,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n", v_rst,v_en,v_objs,v_vb,v_clr,v_pin,v_a,v_rcx,v_rin,v_step,v_start,v_right,v_ref,v_p0,v_p1,v_p2);
      rst=v_rst; en=v_en; objs=v_objs; vblank=v_vb; cxclr=v_clr; pin=v_pin; a=v_a; rcx=v_rcx; rinpt=v_rin;
      step=v_step; start=v_start; right=v_right; ref_=v_ref; pf0=v_p0; pf1=v_p1; pf2=v_p2;
      #5 clk=1; #1
      $fwrite(fo, "%0h %0h %0h %0h %0h\n", cx, inpt, d_out, d_oe, pf);
      #4 clk=0;
    end
    $fclose(fo); $finish;
  end
endmodule

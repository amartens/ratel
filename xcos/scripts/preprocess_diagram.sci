function[preprocessed_diagram, ok] = preprocess_diagram(diagram)
//preprocesses a diagram for HDL generation
//diagram = xcos diagram (eg scs_m)
//preprocessed_diagram = diagram ready for adjusting

  ok = %f; preprocessed_diagram = []; 
  fname = 'preprocess_diagram';

  if strcmp(typeof(diagram), 'diagram'),
    ratel_log(msprintf('%s passed instead of diagram', typeof(diagram))+'\n', [fname, 'error']);
    return;
  end

  dtitle = diagram.props.title;
  temp = diagram;

  //change port output data types of blocks where appropriate to fixed point type.
  //this will propagate when adjust_typ is called
  ratel_log(msprintf('converting output type of blocks to fixed point in %s',dtitle)+'\n', [fname]);
  [temp, ko] = introduce_fixed_point(temp)
  if ~ko,
    msg = msprintf('error while converting output ports of some blocks to fixed point in %s',dtitle);
    ratel_log(msg+'\n', [fname, 'error']);
    return;
  end 

  //TODO bubble inport and outport links to top by searching in all component superblocks for
  //inports and outports, and creating input and output ports and links in diagram
  
  //TODO replace local GOTOs with real links 
  //TODO replace global GOTOs with real links. This may be easiest done by using c_pass1 to 
  //get connection info, then updating diagram using this

  //add blocks to be used during port creation to determine port characteristics
  ratel_log(msprintf('adding port creation helper blocks to %s',dtitle)+'\n', [fname]);
  [temp, ko] = add_port_helpers(temp);
  if ~ko,
    msg = msprintf('error adding port creation helper blocks to diagram %s',dtitle);
    ratel_log(msg+'\n', [fname, 'error']);
    return;
  end 

  preprocessed_diagram = temp;
  ok = %t;
endfunction //preprocess_diagram

function[diagram_with_fp, ok] = introduce_fixed_point(diagram)
//converts output ports of certain blocks to fixed point type
  diagram_with_fp = []; ok = %f
  fname = 'introduce_fixed_point'
  fpblocks = ['inport'] //TODO other block types?

  temp = diagram;
  for i = 1:length(temp.objs), 
    obj = temp.objs(i)
    if typeof(obj) == 'Block',
      if or(obj.gui==fpblocks),
        msg = msprintf('introducing fixed point to %s at offset %d', obj.gui, i);
        ratel_log(msg+'\n', [fname]);
        
        //convert all output ports to fixed point type
        obj.model.outtyp = repmat(9, length(obj.model.outtyp), 1)
        temp.objs(i) = obj
      elseif obj.model.sim=="super"|obj.model.sim=="csuper" then
        msg = msprintf('introducing fixed point to superblock at offset %d', i);
        ratel_log(msg+'\n', [fname]);
        
        //update superblock
        [updated_super, ko] = introduce_fixed_point(obj.model.rpar);
        if ~ko then
          msg = msprintf('error while introducing fixed point in superblock found at %d', i);
          ratel_log(msg+'\n', [fname, 'error']);
        end //if
      
        //update diagram with updated super block
        temp.objs(i).model.rpar = updated_super;
      end //if fpblocks
    end //if Block
  end //for
  diagram_with_fp = temp; ok = %t
endfunction //introduce_fixed_point

function[diagram_with_helpers, ok] = add_port_helpers(diagram)
//adds blocks after input ports and before output ports that will not
//be removed during c_pass1 that will help when generating HDL

  diagram_with_helpers = []; ok = %f;
  fname = 'add_port_helpers';
  in_blocks=["IN_f","INIMPL_f","CLKIN_f","CLKINV_f"]
  out_blocks=["OUT_f","OUTIMPL_f","CLKOUT_f","CLKOUTV_f"]
  d_temp = diagram
 
  //no error checking as check done in calling function
  //that faces externally
 
  for obj_i = 1:length(d_temp.objs),
    obj = d_temp.objs(obj_i);
    n_objs = length(d_temp.objs)

    if typeof(obj) == 'Block' then
      //process input port blocks
      if or(obj.gui==in_blocks) then
        msg = msprintf('processing %s(%d)', obj.gui, obj.model.ipar);
        ratel_log(msg+'\n', [fname]);

        //new link between input port and helper
        lnk = scicos_link()
        lnk.id = 'helper'
        lnk.from = [obj_i, 1, 0]
        lnk.to = [n_objs+1, 1, 1] 

        //construct input helper block
        io = inout('define', 1, msprintf('%s%s', obj.gui, obj.graphics.exprs(1)))
        pout = obj.graphics.pout    

        //link helper to input port's links
        io.graphics.pout = pout       
        //link helper to new link to input port
        io.graphics.pin = n_objs+2
        //change input port's link
        obj.graphics.pout = n_objs+2

        //insert new object, new link, and updated object
        d_temp.objs(n_objs+1) = io
        d_temp.objs(n_objs+2) = lnk
        d_temp.objs(obj_i) = obj
    
        //lastly update existing links to point to helper as source
        d_temp.objs(pout).from = [n_objs+1, 1, 0]

      elseif or(obj.gui==out_blocks) then
        msg = msprintf('processing %s(%d)', obj.gui, obj.model.ipar);
        ratel_log(msg+'\n', [fname]);

        //new link between helper and output port
        lnk = scicos_link()
        lnk.id = 'helper'
        lnk.from = [n_objs+1, 1, 0]
        lnk.to = [obj_i, 1, 1] 

        //construct output helper block
        io = inout('define', 0, msprintf('%s%s', obj.gui, obj.graphics.exprs(1)))
        pin = obj.graphics.pin
        //link helper to link into output port
        io.graphics.pin = pin       
        //link helper to new link to output port
        io.graphics.pout = n_objs+2

        obj.graphics.pin = n_objs+2

        //insert new object, new link, and updated object
        d_temp.objs(n_objs+1) = io
        d_temp.objs(n_objs+2) = lnk
        d_temp.objs(obj_i) = obj
    
        //lastly update existing links to point to helper as destination
        d_temp.objs(pin).to = [n_objs+1, 1, 1]

      elseif obj.model.sim=="super"|obj.model.sim=="csuper" then
        msg = msprintf('adding port helpers to superblock at offset %d', obj_i);
        ratel_log(msg+'\n', [fname]);
        
        //update superblock
        [updated_super, ko] = add_port_helpers(obj.model.rpar);
        if ~ko then
          msg = msprintf('error adding port helpers in superblock found at %d', obj_i);
          ratel_log(msg+'\n', [fname, 'error']);
        end //if
      
        //update diagram with updated super block
        d_temp.objs(obj_i).model.rpar = updated_super;
      end //if super
    end //if Block
  end //for

  diagram_with_helpers = d_temp;
  ok = %t;
endfunction //add_port_helpers

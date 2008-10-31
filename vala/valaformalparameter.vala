/* valaformalparameter.vala
 *
 * Copyright (C) 2006-2008  Jürg Billeter, Raffaele Sandrini
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.

 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.

 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 * Author:
 * 	Jürg Billeter <j@bitron.ch>
 *	Raffaele Sandrini <raffaele@sandrini.ch>
 */

using GLib;
using Gee;

/**
 * Represents a formal parameter in method and callback signatures.
 */
public class Vala.FormalParameter : Symbol {
	/**
	 * The parameter type.
	 */
	public DataType parameter_type {
		get { return _data_type; }
		set {
			_data_type = value;
			_data_type.parent_node = this;
		}
	}

	public ParameterDirection direction { get; set; default = ParameterDirection.IN; }

	/**
	 * Specifies whether the methods accepts an indefinite number of
	 * parameters.
	 */
	public bool ellipsis { get; set; }
	
	/**
	 * Specifies the expression used when the caller doesn't supply an
	 * argument for this parameter.
	 */
	public Expression default_expression { get; set; }
	
	/**
	 * Specifies whether the array length should implicitly be passed
	 * if the parameter type is an array.
	 */
	public bool no_array_length { get; set; }
	
	/**
	 * Specifies whether this parameter holds a value to be assigned to a
	 * construct property. This is only allowed in CreationMethod headers.
	 */
	public bool construct_parameter { get; set; }

	/**
	 * Specifies the position of the parameter in the C function.
	 */
	public double cparameter_position { get; set; }

	/**
	 * Specifies the position of the array length parameter in the C
	 * function.
	 */
	public double carray_length_parameter_position { get; set; }

	/**
	 * Specifies the position of the delegate target parameter in the C
	 * function.
	 */
	public double cdelegate_target_parameter_position { get; set; }

	/**
	 * Specifies the type of the parameter in the C function.
	 */
	public string? ctype { get; set; }

	private DataType _data_type;

	/**
	 * Creates a new formal parameter.
	 *
	 * @param name   parameter name
	 * @param type   parameter type
	 * @param source reference to source code
	 * @return       newly created formal parameter
	 */
	public FormalParameter (string name, DataType parameter_type, SourceReference? source_reference = null) {
		base (name, source_reference);
		this.parameter_type = parameter_type;

		access = SymbolAccessibility.PUBLIC;
	}
	
	/**
	 * Creates a new ellipsis parameter representing an indefinite number of
	 * parameters.
	 */
	public FormalParameter.with_ellipsis (SourceReference? source_reference = null) {
		base (null, source_reference);
		ellipsis = true;

		access = SymbolAccessibility.PUBLIC;
	}

	public override void accept (CodeVisitor visitor) {
		visitor.visit_formal_parameter (this);
	}

	public override void accept_children (CodeVisitor visitor) {
		if (!ellipsis) {
			parameter_type.accept (visitor);
			
			if (default_expression != null) {
				default_expression.accept (visitor);
			}
		}
	}

	public override void replace_type (DataType old_type, DataType new_type) {
		if (parameter_type == old_type) {
			parameter_type = new_type;
		}
	}

	private void process_ccode_attribute (Attribute a) {
		if (a.has_argument ("type")) {
			ctype = a.get_string ("type");
		}
		if (a.has_argument ("array_length_pos")) {
			carray_length_parameter_position = a.get_double ("array_length_pos");
		}
		if (a.has_argument ("delegate_target_pos")) {
			cdelegate_target_parameter_position = a.get_double ("delegate_target_pos");
		}
	}

	/**
	 * Process all associated attributes.
	 */
	public void process_attributes () {
		foreach (Attribute a in attributes) {
			if (a.name == "CCode") {
				process_ccode_attribute (a);
			}
		}
	}

	public FormalParameter copy () {
		if (!ellipsis) {
			var result = new FormalParameter (name, parameter_type, source_reference);
			return result;
		} else {
			return new FormalParameter.with_ellipsis ();
		}
	}

	public override bool check (SemanticAnalyzer analyzer) {
		accept_children (analyzer);

		if (analyzer.context.non_null && default_expression != null) {
			if (default_expression is NullLiteral
			    && !parameter_type.nullable
			    && direction != ParameterDirection.OUT) {
				Report.warning (source_reference, "`null' incompatible with parameter type `%s`".printf (parameter_type.to_string ()));
			}
		}

		if (!ellipsis) {
			if (!is_internal_symbol ()) {
				if (parameter_type is ValueType && !parameter_type.is_real_struct_type ()) {
					analyzer.current_source_file.add_type_dependency (parameter_type, SourceFileDependencyType.HEADER_FULL);
				} else {
					analyzer.current_source_file.add_type_dependency (parameter_type, SourceFileDependencyType.HEADER_SHALLOW);
				}
			}
			analyzer.current_source_file.add_type_dependency (parameter_type, SourceFileDependencyType.SOURCE);

			// check whether parameter type is at least as accessible as the method
			if (!analyzer.is_type_accessible (this, parameter_type)) {
				error = true;
				Report.error (source_reference, "parameter type `%s` is less accessible than method `%s`".printf (parameter_type.to_string (), parent_symbol.get_full_name ()));
				return false;
			}
		}

		/* special treatment for construct formal parameters used in creation methods */
		if (construct_parameter) {
			if (!(parent_symbol is CreationMethod)) {
				error = true;
				Report.error (source_reference, "construct parameters are only allowed in type creation methods");
				return false;
			}

			var method_body = ((CreationMethod) parent_symbol).body;
			var left = new MemberAccess (new MemberAccess.simple ("this"), name);
			var right = new MemberAccess.simple (name);

			method_body.add_statement (new ExpressionStatement (new Assignment (left, right), source_reference));
		}

		return true;
	}
}

public enum Vala.ParameterDirection {
	IN,
	OUT,
	REF
}


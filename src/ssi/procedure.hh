#pragma once

class Object;

class Procedure {
  private:
    Object* formal_arg_names;
    Object* context_args;
    Object* replaced_body;
};

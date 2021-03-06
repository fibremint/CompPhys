/* repeat.c */
/*
  Fitzpatrick.  Computational Physics.  329.pdf
  2.15 Command Line Parameters pp. 77
  
  "
  The main() function may optionally possess special arguments which allow parameters
  to be passed to this function from the operating system.  There are 2 such arguments,
  convetionally called argc and argv.
  
  argc is an integer which is set to the number of parameters passed to main()
  
  argv is an array of pointers to character strings which contain these parameters

  In order to pass one or more parameters to a C program when it is executed from the operating system, 
  parameters must follow the program name on the command line: e.g.
  
  % program-name parameter_1 parameter_2 parameter_3 .. parameter_n

  Program name will be stored in the first item in argv, followed by each of the parameters. 
  Hence, if program name is followed by n parameters there'll be n + 1 entries in argv,
  ranging from argv[0] to argv[n]
  Furthermore, argc will be automatically set equal to n+1
*/

/*
  Program to read and echo data from command line
*/

#include <stdio.h>

int main(int argc, char *argv[])
{
  int i;
  
  for (i=1; i < argc; i++) printf("%s ", argv[i]);
  printf("\n");

  return 0;
}


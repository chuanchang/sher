           Alex Jia <jyang@example.com> Jan 29, 2018

Introduction
~~~~~~~~~~~~
  sher is a framework aimed to test cmdline component with Shell scripts. 

  Traditionally, we'd like mixing case implementation and case design
together to write a case. The great disadvantage of doing like so is
it will produce much redundant codes, and also too overcomplicated and
inflexiable to maintain. Can you imagine to write each single script
for all of the cases? It will be a big effort to finish this task, 
and you will find it will be a tough work for future maintaining.

  For sher, we separate the case implementation from case design.
Somehow, it follows the Unix philosophy: separate policy from mechanism,
separate interfaces with engine, :-).

  In sher, The case implementation are encapsulated as functions,
and then you use these functions to design cases as you want.  we put
all the scripts that for case implementations under directory "lib",
and the final case under "cases". And to distinguish from the general
case, we call them as "tc".

  The advantage of separate the implementation from design is: increasing
the reusability of codes, easy to maintain, easy to read, easy for project
management. (the developer could just focus on the implementing good API,
and the case design could be done by others by using the API to write "tc").

  As we known, for testing, we need much logs for the testing steps, and
also need to count the FAIL and PASS steps, writing the log statements in
"tc" is not a good idea, it increases the work of "tc" writer. As a result,
we generate log statements for "tc" automatically in framework, what you
must do is just write "tc" in a specific format, (see "tc format" below).
It's done by "utils/caser.sh", which we call it as "case reprocesser", :-)

  Directory "cases":

    cases/samples:    sample "tcs" to demonstrate how to use lib functions
                      (by developer) 
 
  Directory "lib":
 
    lib/*.sh:         encapsulation of the basic virsh commands.

  Other directories:

    utils:          scripts that provides service for "lib".


  Important scripts:

    utils/hash.sh:  To do complicated testing, functions need to accept complex
                    parameters, to work around the weakness of Bash's parameters
                    passing, we simulated a hash table. Every lib function that
                    want to be opened as API for "tc" use will use it.
   
Requirements
~~~~~~~~~~~~
  * bash

How to use
~~~~~~~~~~~~
  % ./sher -h
  % ./sher cases/samples/foo.tc
  % ./sher cases/samples/foo.tc cases/samples/bar.tc cases/samples/foobar.tc


tc format
~~~~~~~~~~~~
  A case step format:
    function \
    [TAB]key=value \
    [TAB]key1=value1 \
    [TAB]key2="value2 value3 value4"

  NOTES:
    - "function" must has implementation in the scripts under direcrory "lib"

    - If the "value" has spaces, it must be double-quoted.

    - The format of a case step must be same as we showed above.
        * the "function" MUST be alone in one line, with no key/value pair
        * there MUST be ne no spaces ahead of "function"
        * every key/value pair must beginning with a TAB
        * there MUST be no spaces after "\"

    - You can define variable in case, and use them elsewhere in the case.
      But pls take not every variable name should begin with "__VAR__". And
      if the value of the variable contains spaces. You need double-quote it.
      e.g.

      __VAR__Alex="docker"

      foo \
      [TAB]Alex="$__VAR__Alex"

    - Every case MUST define a summary of the case as following:
      summary="This is a demo"

  That's enough. :-)

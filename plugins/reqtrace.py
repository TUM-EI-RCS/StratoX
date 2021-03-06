#!/usr/bin/env python

"""This file provides support for tracing of low-level requirements
to source code and vice versa.

To use it, annotate subprograms in comments like follows:

    -- @req bar
    procedure foo;

    -- @req foo-fun/1
    procedure foo is
    begin
       null; -- @req blabla
    end foo;

This will link the requirements "foo-fun/1", "bar", and "blabla" from the
database with the procedure foo. For evaluation of coverage and tracing,
use the menu item "requirements".

TODO: 
 - somehow allow completion in comment lines
 - read SPARK annotations and export them as verification means.

(C) 2016 by Martin Becker <becker@rcs.ei.tum.de>

"""

__author__ = "Martin Becker"
__copyright__ = "Copyright 2016, Martin Becker"
__license__ = "GPL"
__version__ = "1.0.1"
__email__ = "becker@rcs.ei.tum.de"
__status__ = "Testing"


import os.path
import re
import GPS
import gps_utils
import text_utils
from modules import Module
from completion import CompletionResolver, CompletionProposal
import completion

# find path of this script and add its subfolder "tools" to the search path for python packages
import inspect, os, sys
tools_folder = os.path.realpath(os.path.abspath(os.path.split(inspect.getfile( inspect.currentframe() ))[0])+ os.sep + "tools")
if tools_folder not in sys.path:
    sys.path.insert(0, tools_folder)
import reqtools

LIGHTGREEN="#D5F5E3"
LIGHTRED="#F9E79F"
LIGHTORANGE="#FFBF00"
DEFAULT_SLOCPERLLR=20

MENUITEMS = """
<submenu before="Window">
      <Title>Requirements</Title>
        <menu action="List Subprogram Requirements">
          <Title>List requirements implemented by subprogram</Title>
        </menu>
        <menu><title/></menu>
        <menu action="List Open Requirements">
          <Title>Show open requirements</Title>
        </menu>
        <menu action="Mark Unjustified Code">
          <Title>Mark unjustified code</Title>
        </menu>
        <menu action="Check Density">
        <title>Check Density of Requirements</title>
        </menu>
        <menu><title/></menu>
        <menu action="List All Requirements">
          <Title>Show all requirements</Title>
        </menu>
</submenu>
<action name="Some Other Action">
    <shell lang="python">print 'a'</shell>
</action>
"""

PROPERTIES="""
 <project_attribute
      name="ReqFile"
      package="Requirements"
      editor_page="Requirements"
      editor_section="Single"
      description="The path for the sqlite3 file storing the requirements." >
      <string type="file" default="./requirements.db" />
  </project_attribute>
 <project_attribute
      name="SlocPerLLR"
      package="Requirements"
      editor_page="Requirements"
      editor_section="Single"
      description="The maximum number of lines (source code) per low-level requirement." >
      <string mininum="1" default="20" />
  </project_attribute>
"""

COMPLETION_PREFIX="Req."

class Req_Resolver(CompletionResolver):
    """
       The Requirements Resolver class that inherits completion.CompletionResolver.
    """

    reqfile = None
    
    def __init__(self):
        self.__prefix = None
        pass

    def set_reqfile(self,filename):
        self.reqfile=filename
        print "completion: db=" + self.reqfile
    
    def get_completions(self, loc):
        """
        Overriding method. Only called outside of comments
        """
        
        # FIXME: cache this
        if not self.reqfile:
            print "Completion: no database"
            return
        with reqtools.Database() as db:
            db.connect(self.reqfile);
            reqs = db.get_requirements();
            if not reqs:
                return []
            
        completionset = [CompletionProposal(
            name= "req " + k + " (" + props["description"] +")",
            label= COMPLETION_PREFIX + " " + k,
            documentation=props["description"])
            for k,props in reqs.iteritems()]
        
        return completionset
            
    def get_completion_prefix(self, loc):
        return [COMPLETION_PREFIX]

class Reqtrace(object):

    reqfile = None
    target_slocperllr = None
    _resolver = Req_Resolver()
    
    def __init__(self):
        """
        Various initializations done before the gps_started hook
        """
        
        #self.port_pref = GPS.Preference("Plugins/reqtrace/port")

        XML = """
        <documentation_file>
           <name>http://docs.python.org/2/tutorial/</name>
           <descr>Requirements Tracer tutorial</descr>
           <menu>/Help/Requirements/Tutorial</menu>
           <category>Scripts</category>
        </documentation_file>
        <documentation_file>
          <shell lang="python">"""

        XML += """GPS.execute_action('display reqtrace help')</shell>
          <descr>Requirements Tracer</descr>
          <menu>/Help/Requirements/Help</menu>
          <category>Scripts</category>
        </documentation_file>
        """

        XML += PROPERTIES;
        
        XML += MENUITEMS;

        GPS.parse_xml(XML)

    def gps_started(self):
        """
        Initializations done after the gps_started hook (add menu)
        """

        # declare local function as action (menu, shortcut, etc.)
        gps_utils.make_interactive(
            callback=self.mark_unjustified_code,
            name='Mark Unjustified Code')

        gps_utils.make_interactive(
            callback=self.check_density,
            name='Check Density')

        # declare local function as action (menu, shortcut, etc.)
        gps_utils.make_interactive(
            callback=self.list_subp_requirements,
            name='List Subprogram Requirements')

        gps_utils.make_interactive(
            callback=self.list_all_requirements,
            name='List All Requirements')

        # context menu in editor
        #gps_utils.make_interactive(
        #    callback=self.reload_file,
        #    name='MBe reload requirements',
        #    contextual='Requirements/Reload')

        GPS.Hook("project_view_changed").add(self._project_recomputed)
        GPS.Hook("before_exit_action_hook").add(self._before_exit)
        GPS.Hook("project_changed").add(self._project_loaded)
        GPS.Hook("project_saved").add(self._project_loaded)
        GPS.Completion.register(self._resolver, "ada")        

    def check_density(self):
        """
        Count the number of SLOC per requirements in current file and warn if density is
        too low. We are targeting at most 20SLOC/requirement. Note that this
        function only counts the number of annotations, not checking whether
        they actually exist in the database.
        """
        print ""
        # FIXME: we must make sure that gnatinspect.db is up-to-date. How? Rebuilding helps.

        # get current cursor
        try:
            ctx = GPS.current_context()
            curloc = ctx.location()
            file = curloc.file()
            editor = GPS.EditorBuffer.get(file)
        except:
            return

        GPS.Locations.remove_category("Low LLR density");
        GPS.Editor.register_highlighting("Low LLR density", LIGHTORANGE)
        GPS.Locations.remove_category("Good LLR density");
        GPS.Editor.register_highlighting("Good LLR density", LIGHTGREEN)

        
        # iterate over all subprograms (requires cross-referencing to work)
        for ent,loc in file.references(kind='body'):
            if ent.is_subprogram():
                #print "entity: " + ent.name() + " at " + str(loc)
                # extract requirements for the entity
                if editor is not None:
                    edloc = editor.at(loc.line(), loc.column())
                    (startloc, endloc) = self._get_enclosing_block(edloc)
                    (name,reqs) = self._get_subp_requirements (editor, loc, unchecked=True) #<-- different to mark_unjustified_code
                    # name should equal ent.name
                    if (name.strip() != ent.name().strip()):
                        print "Warning: GPS Entity name '" + ent.name() + "' differs from found entity '" + name + "'"
                    rcount = len(reqs)
                    sloc = endloc.line() - startloc.line() + 1
                    if rcount > 0:                        
                        slocperllr = sloc/rcount
                    else:
                        slocperllr = float("inf")
                    if slocperllr > self.target_slocperllr:
                        category = "Low LLR density"
                    else:
                        category = "Good LLR density"
                    print "Entity '" + name + "' has not enough requirements per SLOC (" + str(slocperllr) + ")"
                    GPS.Locations.add(category=category,
                                  file=file,
                                  line=loc.line(),
                                  column=loc.column(),
                                  message="SLOC per LLR is " + str(slocperllr) + " (" + str(rcount) + " requirements for " + str(sloc) + " SLOC)",
                                  highlight=category)

        
    def mark_unjustified_code(self):
        """
        Iterate over all files and subprograms and warn if a subprogram has no requirements.
        Note that requirements are checked for their exsistence against a database. Only
        existing requirements are considered.
        """
        print ""

        # FIXME: we must make sure that gnatinspect.db is up-to-date. How? Rebuilding helps.

        # get current cursor
        try:
            ctx = GPS.current_context()
            curloc = ctx.location()
            file = curloc.file()
            editor = GPS.EditorBuffer.get(file)
        except:
            return

        GPS.Locations.remove_category("Unjustified_Code");
        GPS.Editor.register_highlighting("Unjustified_Code", LIGHTRED)

        # iterate over all subprograms (requires cross-referencing to work)
        for ent,loc in file.references(kind='body'):
            if ent.is_subprogram():
                #print "entity: " + ent.name() + " at " + str(loc)
                # extract requirements for the entity
                if editor is not None:
                    edloc = editor.at(loc.line(), loc.column())
                    #(startloc, endloc) = self._get_enclosing_block(edloc)
                    (name,codereqs) = self._get_subp_requirements (editor, loc)
                    # filter out those not in the database
                    reqs={ k : v for k,v in codereqs.iteritems() if v["in_database"] }                    
                    # name should equal ent.name
                    if (name.strip() != ent.name().strip()):
                        print "Warning: GPS Entity name '" + ent.name() + "' differs from found entity '" + name + "'"
                    if not reqs:
                        print "Entity '" + name + "' has ZERO requirements"
                        GPS.Locations.add(category="Unjustified_Code",
                                  file=file,
                                  line=loc.line(),
                                  column=loc.column(),
                                  message="no requirements for '" + name + "'",
                                  highlight="Unjustified_Code")
                    else:
                        rnames = [k for k,v in reqs.iteritems()]
                        print "Entity '" + name + "' has " + str(len(reqs)) + " valid requirements: " + str(rnames)


    def _extract_comments(self, sourcecode, linestart, filename):
        """
        returns only the comments of ada source code.
        list of dict ("text" : <comment text>, "file": <path>, "line" : <int>, "col", <int>)
        """

        comment = []
        l = linestart
        for line in sourcecode.splitlines():
            pos = line.find("--")
            if pos >=0:
                comment.append({"text" : line[pos+2:], "file": filename, "line" : l, "col" : pos + 2})
            l = l + 1
        return comment

    def _extract_requirements(self, comment):
        """
        parse comments and return the referenced requirements
        """
        reqs = {}

        pattern = re.compile("@req (\S+)")
        for c in comment:
            results = re.finditer(pattern, c["text"])
            for match in results:
                colstart = match.start(0) + c["col"] + 1
                reqname = match.group(1)
                if not reqname in reqs:
                    reqs[match.group(1)] = {"locations" : []};
                reqs[match.group(1)]["locations"].append({"file" : c["file"], "line" : c["line"], "col" : colstart});

        # TODO: postprocessing. ACtually check whether requirements exist in database, otherwise mark them as invalid

        return reqs

    def _check_requirements(self, codereqs):
        """
        Check every entry in reqs for presence in the database. Add an extra dict entry "in_database" with the result
        """
        with reqtools.Database() as db:
            db.connect(self.reqfile);
            result = db.get_requirements();
            if not result:
                for k,v in codereqs.iteritems():
                    codereqs[k]["in_database"] = False
            else:
                dbreqs = set(k.lower() for k in result)
                for k,v in codereqs.iteritems():
                    if k.lower() in dbreqs:
                        codereqs[k]["in_database"] = True
                    else:
                        codereqs[k]["in_database"] = False
        return codereqs
    
    def _get_subp_requirements(self, editor, fileloc, unchecked=False):
        """
        from given location find subprogram entity, and then check both its body and spec for requirements
        @param unchecked: if True, then the database is not queried for existence/validity of code refs. Faster w/o check.
        return: name of subp, dict of requirements
        """
        # 1. get entity belonging to cursor
        (entity, loccodestart, loccodeend) = self._get_enclosing_entity(fileloc)
        if not entity:
            print "No enclosing entity found"
            return None, None

        name = entity.name()

        # extract requirements from the range
        editor = GPS.EditorBuffer.get(fileloc.file())
        reqs = self._get_requirements_in_range (editor, loccodestart, loccodeend)

        # 2. find the counterpart (spec <=> body) and also look there
        try:
            locbody = entity.body()
        except:
            locbody = None
        try:
            locspec = entity.declaration()
        except:
            locspec = None
        is_body = locbody and locbody.line() == loccodestart.line()

        reqs_other = None
        if is_body and locspec:
            #print "is body => spec in " + str(locspec.file())
            editor = GPS.EditorBuffer.get(locspec.file())
            (entity, loccodestart, loccodeend) = self._get_enclosing_entity(locspec)
            reqs_other = self._get_requirements_in_range (editor, loccodestart, loccodeend)
        if not is_body and locbody:
            #print "is spec => body in " + str(locbody.file())
            editor = GPS.EditorBuffer.get(locbody.file())
            (entity, loccodestart, loccodeend) = self._get_enclosing_entity(locbody)
            reqs_other = self._get_requirements_in_range (editor, loccodestart, loccodeend)

        # merge dicts (FIXME: double entries)        
        if reqs_other:
            for k,v in reqs_other.iteritems():
                if not k in reqs:
                    reqs[k] = v
                else:
                    reqs[k]["locations"].extend(v["locations"])

        # all done
        if not unchecked:
            reqs = self._check_requirements(reqs)
        return name, reqs

    def _get_requirements_in_range(self, editor, locstart0, locend0):
        (locstart, locend) = self._widen_withcomments(locstart0, locend0)
        if locstart is None or locend is None:
            print "Error getting subprogram range"
            return None

        # now extract all comments from range
        sourcecode = self._get_buffertext(editor,locstart,locend)
        # print "src=" + str(sourcecode)
        comments = self._extract_comments(sourcecode,locstart.line(), str(locstart.buffer().file()))
        return self._extract_requirements(comments)

    def _show_locations(self,reqs):
        """
        show requirements in location window
        """
        if not reqs:
            return

        GPS.Editor.register_highlighting("Valid Requirements", LIGHTGREEN)
        GPS.Editor.register_highlighting("Invalid Requirements", LIGHTORANGE)
        for req,values in reqs.iteritems():
            for ref in values["locations"]: # each requirement can have multiple references
                if values["in_database"]:
                    category = "Valid Requirements"
                    txt="References " + req;
                else:
                    category = "Invalid Requirements"
                    txt="Nonexisting requirement " + req;
                GPS.Locations.add(category=category,
                                  file=GPS.File(ref["file"]),
                                  line=ref["line"],
                                  column=ref["col"],
                                  message=txt,
                                  highlight=category)


    def list_all_requirements(self):
        """
        Dump all requirements from database in Messages Window.
        """
        print ""
        print "List all requirements:"
        with reqtools.Database() as db:
            db.connect(self.reqfile);
            reqs = db.get_requirements();
            if not reqs:
                print " No requirements found"
            else:
                for k,v in reqs.iteritems():
                    print " - " + k + ": " + str(v)


    def list_subp_requirements(self):
        """
        List all requirements references by the subprogram at cursor position.
        Note that the database is checked for existence of requirements.
        Annotations referring to non-existing requirements are marked as invalid.
        """
        print ""

        # get current cursor
        ctx = GPS.current_context()
        curloc = ctx.location()
        editor = GPS.EditorBuffer.get(curloc.file())

        (name, reqs) = self._get_subp_requirements (editor, curloc)
        if reqs:
            self._show_locations(reqs)
            print "Requirements in '" + name + "':"
            for k,v in reqs.iteritems():
                print " - " + k + ": " + str(v)
        else:
            print "No requirements referenced in '" + name + "'"
          
    def _project_loaded (self, hook_name):
        # path to database
        self.reqfile = GPS.Project.root().get_attribute_as_string ("ReqFile", "Requirements")
        prjdir = GPS.Project.root().file().directory()
        if not self.reqfile:
            self.reqfile = prjdir + os.path.sep + "requirements.db"
        else:
            if not os.path.isabs(self.reqfile):
                self.reqfile = prjdir + os.path.sep + self.reqfile        
        print "Requirements Database=" + self.reqfile

        # sloc per LLR ratio
        tmp = GPS.Project.root().get_attribute_as_string ("SlocPerLLR", "Requirements")
        if not tmp:
            self.target_slocperllr = DEFAULT_SLOCPERLLR
        else:
            try:
                self.target_slocperllr = int(tmp)
            except:
                self.target_slocperllr = DEFAULT_SLOCPERLLR

        # register completion resolver
        self._resolver.set_reqfile(self.reqfile)
                
            
    def _project_recomputed(self, hook_name):
        """
        if python is one of the supported language for the project, add various
        predefined directories that may contain python files, so that shift-F3
        works to open these files as it does for the Ada runtime
        """

        GPS.Project.add_predefined_paths(
            sources="%splug-ins" % GPS.get_home_dir())
        try:
            GPS.Project.root().languages(recursive=True).index("python")
            # The rest is done only if we support python
            GPS.Project.add_predefined_paths(sources=os.pathsep.join(sys.path))
        except:
            pass

    def _get_enclosing_block(self, cursor):
        blocks = {"CAT_PROCEDURE": 1, "CAT_FUNCTION": 1, "CAT_ENTRY": 1,
                    "CAT_PROTECTED": 1, "CAT_TASK": 1, "CAT_PACKAGE": 1}

        if cursor.block_type() == "CAT_UNKNOWN":
            return None, None

        min = cursor.buffer().beginning_of_buffer()
        max = cursor.buffer().end_of_buffer()
        while not (cursor.block_type() in blocks) and cursor > min:
            cursor = cursor.block_start() - 1

        if cursor <= min:
            return None, None

        codestart = cursor.block_start() # gives a cursor
        codeend = cursor.block_end()
        return codestart, codeend

    def _widen_withcomments(self, codestart, codeend):
        """
        Widens the given bounds to include directly
        preceeding and succeeding comments
        """

        min = codestart.buffer().beginning_of_buffer()
        max = codestart.buffer().end_of_buffer()

        # look for comments lines directly before and after block and widen cursors accordingly
        for dir in [-1, 1]:
            if dir == -1:
                doccursor = codestart
                boundary = min
            else:
                doccursor = codeend
                boundary = max
            lastvalid = doccursor
            while True:
                if doccursor == boundary:
                    break
                doccursor = doccursor.forward_line(dir)
                line = codestart.buffer().get_chars(doccursor.beginning_of_line(), doccursor.end_of_line())
                iscomment = line.strip().startswith("--")
                if not iscomment:
                    break
                else:
                    lastvalid = doccursor
            # apply the widened bound
            if dir == -1:
                codestart = lastvalid
            else:
                codeend = lastvalid
        return codestart, codeend

    def _get_buffertext(self, e, beginning, end):
        """
        Return the contents of a buffer between two locations
        """
        txt=""
        if beginning.line() != end.line():
            for i in range(beginning.line(), end.line()+1):
                if i == beginning.line:
                    col0 = beginning.col()
                else:
                    col0 = 1
                txt = txt + e.get_chars(e.at(i, col0), e.at(i, 1).end_of_line())
        else:
            txt = e.get_chars(end.beginning_of_line(), end.end_of_line())
        return txt

    def _get_enclosing_entity(self, curloc):
        """
        Return the entity that encloses the current cursor
        """

        buf = GPS.EditorBuffer.get(curloc.file(), open=False)
        if buf is not None:
            edloc = buf.at(curloc.line(), curloc.column())
            (start_loc, end_loc) = self._get_enclosing_block(edloc)
        else:
            return None, None, None

        if not start_loc:
            return None, None, None
        name = edloc.subprogram_name() # FIXME: not right.

        # [entity_bounds] returns the beginning of the col/line of the
        # definition/declaration. To be able to call GPS.Entity, we need to be
        # closer to the actual subprogram name. We get closer by skipping the
        # keyword that introduces the subprogram (procedure/function/entry etc.)

        id_loc = start_loc
        id_loc = id_loc.forward_word(1)
        try:
            return GPS.Entity(name, id_loc.buffer().file(),id_loc.line(), id_loc.column()), start_loc, end_loc
        except:
            return None, None, None

    def _before_exit(self, hook_name):
        """Called before GPS exits"""
        return 1


# Create the class once GPS is started, so that the filter is created
# immediately when parsing XML, and we can create our actions.
module = Reqtrace()
GPS.Hook("gps_started").add(lambda h: module.gps_started())

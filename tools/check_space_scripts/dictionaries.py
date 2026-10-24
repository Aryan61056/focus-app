"""Scripting dictionaries for the stand-in Arc and Dia (FakeSpaces.swift), shaped like the real ones read with `sdef /Applications/Arc.app`
and `sdef /Applications/Dia.app`: the same class, element, property and command names. Only what Hushd's scripts use is here."""
common_cmds = '''
<command name="close" code="coreclos" description="Close"><direct-parameter description="target" type="specifier"/></command>
<command name="count" code="corecnte" description="Return the number of elements of a particular class within an object."><cocoa class="NSCountCommand"/><direct-parameter description="the object" type="specifier"/><parameter name="each" code="kocl" description="class" type="type" optional="yes"><cocoa key="ObjectClass"/></parameter><result description="count" type="integer"/></command>
<command name="select" code="CrSelect" description="Select the tab."><direct-parameter description="tab" type="specifier"/></command>
<command name="focus" code="SpaFocus" description="Hushd."><direct-parameter description="target" type="specifier"/></command>
'''
arc = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
<dictionary title="Fake Arc"><suite name="Standard Suite" code="core" description="x">
<class name="application" code="capp" description="app"><cocoa class="FApp"/>
 <element description="windows" type="window"><cocoa key="appleScriptWindows"/></element>
 <property name="name" code="pnam" type="text" access="r"/></class>
<class name="window" code="WiND" description="w" plural="windows"><cocoa class="FWindow"/>
 <element description="spaces" type="space"><cocoa key="appleScriptSpaces"/></element>
 <element description="tabs" type="tab"><cocoa key="appleScriptTabs"/></element>
 <property name="id" code="ID  " type="text" access="r"><cocoa key="id"/></property>
 <property name="name" code="pnam" type="text" access="r"><cocoa key="title"/></property>
 <property name="index" code="pidx" type="integer"><cocoa key="orderedIndex"/></property>
 <property name="active tab" code="acTa" type="tab" access="r"><cocoa key="activeTab"/></property>
 <property name="active space" code="acSp" type="space" access="r"><cocoa key="activeSpace"/></property>
 <property name="incognito" code="inco" type="boolean"><cocoa key="isIncognito"/></property>
 <property name="mode" code="mode" type="text"><cocoa key="mode"/></property></class>
<class name="tab" code="tAbB" description="t" plural="tabs"><cocoa class="FTab"/>
 <property name="id" code="ID  " type="text" access="r"><cocoa key="id"/></property>
 <property name="title" code="pnam" type="text" access="r"><cocoa key="title"/></property>
 <property name="URL" code="URL " type="text" access="rw"><cocoa key="URL"/></property>
 <property name="loading" code="ldng" type="boolean" access="r"/>
 <responds-to command="select"><cocoa method="select:"/></responds-to>
 <responds-to command="close"><cocoa method="close:"/></responds-to></class>
<class name="space" code="sPaC" description="s" plural="spaces"><cocoa class="FSpace"/>
 <property name="id" code="ID  " type="text" access="r"><cocoa key="id"/></property>
 <property name="title" code="pnam" type="text" access="r"><cocoa key="title"/></property>
 <element description="tabs" type="tab"><cocoa key="appleScriptTabs"/></element>
 <responds-to command="focus"><cocoa method="focus:"/></responds-to></class>
''' + common_cmds + '</suite></dictionary>\n'
dia = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
<dictionary title="Fake Dia"><suite name="Dia" code="DiaS" description="x">
<class name="application" code="capp" description="app"><cocoa class="FApp"/>
 <element name="windows" description="windows" type="window" access="r"><cocoa key="appleScriptWindows"/></element>
 <property name="name" code="pnam" type="text" access="r"/></class>
<class name="window" code="cwin" description="w" plural="windows"><cocoa class="FWindow"/>
 <property name="id" code="ID  " type="text" access="r"><cocoa key="windowId"/></property>
 <property name="name" code="pnam" type="text" access="r"><cocoa key="name"/></property>
 <property name="active tab" code="acTa" type="tab" access="r"><cocoa key="activeTab"/></property>
 <property name="active profile" code="acPr" type="profile" access="r"><cocoa key="activeProfile"/></property>
 <property name="index" code="pidx" type="integer" access="r"><cocoa key="orderedIndex"/></property>
 <element name="tabs" description="tabs" type="tab" access="rw"><cocoa key="appleScriptTabs"/></element>
 <element name="profiles" description="profiles" type="profile" access="r"><cocoa key="appleScriptProfiles"/></element></class>
<class name="tab" code="DiaT" description="t" plural="tabs"><cocoa class="FTab"/>
 <property name="id" code="ID  " type="text" access="r"><cocoa key="tabId"/></property>
 <property name="title" code="pnam" type="text" access="r"><cocoa key="title"/></property>
 <property name="URL" code="URL " type="text" access="rw"><cocoa key="URL"/></property>
 <property name="loading" code="ldng" type="boolean" access="r"><cocoa key="loading"/></property>
 <responds-to command="focus"><cocoa method="focus:"/></responds-to>
 <responds-to command="close"><cocoa method="close:"/></responds-to></class>
<class name="profile" code="DiaP" description="p" plural="profiles"><cocoa class="FProfile"/>
 <property name="name" code="pnam" type="text" access="r"><cocoa key="name"/></property>
 <property name="index" code="pidx" type="integer" access="r"><cocoa key="orderedIndex"/></property>
 <element name="tabs" description="tabs" type="tab" access="rw"><cocoa key="appleScriptTabs"/></element>
 <responds-to command="focus"><cocoa method="focus:"/></responds-to></class>
<command name="count" code="corecnte" description="Return the number of elements of a particular class within an object."><cocoa class="NSCountCommand"/><direct-parameter description="the object" type="specifier"/><parameter name="each" code="kocl" description="class" type="type" optional="yes"><cocoa key="ObjectClass"/></parameter><result description="count" type="integer"/></command>
<command name="close" code="coreclos" description="Close"><direct-parameter description="target" type="specifier"/></command>
<command name="focus" code="DiaTabFc" description="Hushd a tab or profile."><direct-parameter description="target" type="specifier"/></command>
</suite></dictionary>
'''

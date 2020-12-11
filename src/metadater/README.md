# Description of Metadata file

Metadata configuration file is a xml file with two defined namespaces: ParCzech (pcz:) and TEI (tei:). ParCzech namespace control configuration and elements in TEI namespaces are directly included in to a target file.


```
<?xml version="1.0" encoding="utf-8"?>
<pcz:ParCzech xmlns="http://www.tei-c.org/ns/1.0" xmlns:pcz="http://ufal.mff.cuni.cz/parczech/ns/1.0">

  <pcz:meta pcz:name="NAME1">
    <pcz:item pcz:dep="NAME2" /> <!-- call dependency NAME2 at this place -->
    <pcz:item pcz:xpath="/tei:TEI/tei:teiHeader/tei:fileDesc/tei:editionStmt"> <!-- xpath contains place in enritched tei document -->
      <pcz:test> <!-- Continue if result is true (in this case no edition is set) -->
        <pcz:false pcz:xpath="/tei:TEI/tei:teiHeader/tei:fileDesc/tei:editionStmt/edition" />
      </pcz:test>
      <pcz:tei><!-- all subelements of tei are included -->
        <edition>TEST A</edition>
      </pcz:tei>
    </pcz:item>
  </pcz:meta>

  <pcz:meta pcz:name="NAME2">
    <pcz:item pcz:xpath="/tei:TEI/tei:teiHeader/tei:fileDesc/tei:titleStmt">
      <pcz:tei>
        <respStmt>
          <persName>John Doe</persName>
          <resp xml:lang="en">XML formating</resp>
        </respStmt>
      </pcz:tei>
    </pcz:item>
  </pcz:meta>

</pcz:ParCzech>
```

Every `<pcz:meta>` target can be called single time - looping dependencies is not possible.


# Recomended structure for ParCzech

## ParCzech

Common metadata for all possible ParCzech corpora.

### ParCzech.ann

Common metadata for annotated data (depends on ParCzech `<pcz:item pcz:dep="ParCzech" />`)

## ParCzechPS + ParCzechPS.ann

For data from Chamber of Deputies.

## ParCzechPS7 + ParCzechPS7.ann

For a single term

## ParCzechPS-2.0 + ParCzechPS-2.0.ann

For a version of corpus (type of annotations, document structure, ...)

## ParCzechPS7-2.0 + ParCzechPS7-2.0.ann

Release
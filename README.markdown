The FwikiMail module lets you e-mail stuff to your fwiki wiki. If you're like
me and you keep your entire life (notes, to-do lists, projects, goals, etc.) in
a fwiki wiki, this is 1,000% awesome.

## How to make edits

### Create or replace a page

To create or replace the page "grocery list":

    >grocery list
    bananas, duct tape, hot sauce

### Append to a page

    >>todo list
    walk the dog, buy fish, read some books

### Prepend to a page

    <<todo list
    important: buy birthday present for self


## Pro tips

### Use multiple blank lines in edits

Multiple blank lines after an edit directive won't break anything:

    >>class notes
    
    
    
    this paragraph has
    a lot of space
    above it


### Put multiple edits in one e-mail

Just separate them with two newlines:

    >>todo list
    make a todo list
    
    
    >awesome idea
    this is an awesome idea
    
    
    <<projects
    go shopping

### Use the Subject: field

You can put the first line of your edits in the *Subject:* header of your e-mail. In the following example, pretend the line starting with *Subject:* is an input box in your e-mail client.

    Subject: >>projects
    
    - shave the house

### Add to a list-like page alphabetically

Imagine you have an alphabetical projects page like this:

    - e-mail mom
    - fix bike
    - sell textbooks on ebay

You could add an item to the list with this syntax:

    <projects
    - paint the dog

Then *paint the dog* will be inserted between *fix bike* and *sell textbooks on ebay*.


// source: less/extend-visitor.js 2.5.0 lines 91-451

part of visitor.less;

class ProcessExtendsVisitor extends VisitorBase {
  Visitor _visitor;

  List<List<Extend>> allExtendsStack;
  int extendChainCount = 0;
  Map<String, bool> extendIndicies;

  ///
  ProcessExtendsVisitor() {
    _visitor = new Visitor(this);

//2.3.1
//  var ProcessExtendsVisitor = function() {
//      this._visitor = new Visitor(this);
//  };
  }

  ///
  run(Node root) {
    ExtendFinderVisitor extendFinder = new ExtendFinderVisitor();
    extendIndicies = {};
    extendFinder.run(root);
    if (!extendFinder.foundExtends) return root;
    root.allExtends = root.allExtends.sublist(0)..addAll(doExtendChaining(root.allExtends, root.allExtends));
    allExtendsStack = [root.allExtends];
    var newRoot = _visitor.visit(root);
    checkExtendsForNonMatched(root.allExtends);
    return newRoot;

//2.3.1
//  run: function(root) {
//      var extendFinder = new ExtendFinderVisitor();
//      this.extendIndicies = {};
//      extendFinder.run(root);
//      if (!extendFinder.foundExtends) { return root; }
//      root.allExtends = root.allExtends.concat(this.doExtendChaining(root.allExtends, root.allExtends));
//      this.allExtendsStack = [root.allExtends];
//      var newRoot = this._visitor.visit(root);
//      this.checkExtendsForNonMatched(root.allExtends);
//      return newRoot;
//  },
  }

  ///
  checkExtendsForNonMatched(List<Extend> extendList) {
    Logger logger = new Logger();
    Map<String, bool> indicies = extendIndicies;
    extendList.retainWhere((extend) {
      return (!extend.hasFoundMatches && extend.parent_ids.length == 1);
    });
    extendList.forEach((extend){
      String selector = '_unknown_';
      String key;
      try {
        selector = extend.selector.toCSS(new Contexts());
      } catch(_){}

      key = extend.index.toString() + ' ' + selector;
      if (!indicies.containsKey(key)) {
        indicies[key] = true;
        logger.warn("extend '$selector' has no matches");
      }
    });

//2.3.1
//  checkExtendsForNonMatched: function(extendList) {
//      var indicies = this.extendIndicies;
//      extendList.filter(function(extend) {
//          return !extend.hasFoundMatches && extend.parent_ids.length == 1;
//      }).forEach(function(extend) {
//              var selector = "_unknown_";
//              try {
//                  selector = extend.selector.toCSS({});
//              }catch(_){}
//
//              if(!indicies[extend.index + ' ' + selector]) {
//                  indicies[extend.index + ' ' + selector] = true;
//                  logger.warn("extend '" + selector + "' has no matches");
//              }
//          });
//  },
  }

  ///
  /// Chaining is different from normal extension.. if we extend an extend then we are not just copying, altering and pasting
  /// the selector we would do normally, but we are also adding an extend with the same target selector
  /// this means this new extend can then go and alter other extends
  ///
  /// this method deals with all the chaining work - without it, extend is flat and doesn't work on other extend selectors
  /// this is also the most expensive.. and a match on one selector can cause an extension of a selector we had already processed if
  /// we look at each selector at a time, as is done in visitRuleset
  ///
  ///
  List<Extend> doExtendChaining(List<Extend> extendsList, List<Extend> extendsListTarget, [int iterationCount = 0]) {
    int extendIndex; // extendsList iterator
    int targetExtendIndex; //extendsListTarget iterator
    List<MatchSelector> matches;
    List<Extend> extendsToAdd = [];
    List<Selector> newSelector;
    ProcessExtendsVisitor extendVisitor = this;
    List<Selector> selectorPath;
    Extend extend;
    Extend targetExtend;
    Extend newExtend;

    // loop through comparing every extend with every target extend.
    // a target extend is the one on the ruleset we are looking at copy/edit/pasting in place
    // e.g.  .a:extend(.b) {}  and .b:extend(.c) {} then the first extend extends the second one
    // and the second is the target.
    // the seperation into two lists allows us to process a subset of chains with a bigger set, as is the
    // case when processing media queries
    for (extendIndex = 0; extendIndex < extendsList.length; extendIndex++) {
      for (targetExtendIndex = 0; targetExtendIndex < extendsListTarget.length; targetExtendIndex++) {
        extend = extendsList[extendIndex];
        targetExtend = extendsListTarget[targetExtendIndex];

        // look for circular references
        if (extend.parent_ids.indexOf(targetExtend.object_id) >= 0) continue;

        // find a match in the target extends self selector (the bit before :extend)
        selectorPath = [targetExtend.selfSelectors[0]];
        matches = extendVisitor.findMatch(extend, selectorPath);

        if (matches.isNotEmpty) {
          extend.hasFoundMatches = true;

          //we found a match, so for each self selector.
          extend.selfSelectors.forEach((selfSelector) {
            //process the extend as usual
            newSelector = extendVisitor.extendSelector(matches, selectorPath, selfSelector);

            // but now we create a new extend from it
            newExtend = new Extend(targetExtend.selector, targetExtend.option, 0);
            newExtend.selfSelectors = newSelector;

            // add the extend onto the list of extends for that selector
            newSelector.last.extendList = [newExtend];

            // record that we need to add it.
            extendsToAdd.add(newExtend);
            newExtend.ruleset = targetExtend.ruleset;

            // remember its parents for circular references
            newExtend.parent_ids
              ..addAll(targetExtend.parent_ids)
              ..addAll(extend.parent_ids);

            // only process the selector once.. if we have :extend(.a,.b) then multiple
            // extends will look at the same selector path, so when extending
            // we know that any others will be duplicates in terms of what is added to the css
            if (targetExtend.firstExtendOnThisSelectorPath) {
              newExtend.firstExtendOnThisSelectorPath = true;
              targetExtend.ruleset.paths.add(newSelector);
            }
          });
        }
      }

    }

    if (extendsToAdd.isNotEmpty) {
      // try to detect circular references to stop a stack overflow.
      // may no longer be needed.
      this.extendChainCount++;
      if (iterationCount > 100) {
        String selectorOne = r'{unable to calculate}';
        String selectorTwo = r'{unable to calculate}';
        try {
          selectorOne = extendsToAdd[0].selfSelectors[0].toCSS(null);
          selectorTwo = extendsToAdd[0].selector.toCSS(null);
        } catch (e) {}
        throw new LessExceptionError(new LessError(
            message: 'extend circular reference detected. One of the circular extends is currently:${selectorOne}:extend(${selectorTwo})'
         ));
      }

      // now process the new extends on the existing rules so that we can handle
      // a extending b extending c ectending d extending e...
      return extendsToAdd..addAll(extendVisitor.doExtendChaining(extendsToAdd, extendsListTarget, iterationCount+1));
    } else {
      return extendsToAdd;
    }

//2.3.1
//  doExtendChaining: function (extendsList, extendsListTarget, iterationCount) {
//      //
//      // chaining is different from normal extension.. if we extend an extend then we are not just copying, altering
//      // and pasting the selector we would do normally, but we are also adding an extend with the same target selector
//      // this means this new extend can then go and alter other extends
//      //
//      // this method deals with all the chaining work - without it, extend is flat and doesn't work on other extend selectors
//      // this is also the most expensive.. and a match on one selector can cause an extension of a selector we had already
//      // processed if we look at each selector at a time, as is done in visitRuleset
//
//      var extendIndex, targetExtendIndex, matches, extendsToAdd = [], newSelector, extendVisitor = this, selectorPath,
//          extend, targetExtend, newExtend;
//
//      iterationCount = iterationCount || 0;
//
//      //loop through comparing every extend with every target extend.
//      // a target extend is the one on the ruleset we are looking at copy/edit/pasting in place
//      // e.g.  .a:extend(.b) {}  and .b:extend(.c) {} then the first extend extends the second one
//      // and the second is the target.
//      // the seperation into two lists allows us to process a subset of chains with a bigger set, as is the
//      // case when processing media queries
//      for(extendIndex = 0; extendIndex < extendsList.length; extendIndex++){
//          for(targetExtendIndex = 0; targetExtendIndex < extendsListTarget.length; targetExtendIndex++){
//
//              extend = extendsList[extendIndex];
//              targetExtend = extendsListTarget[targetExtendIndex];
//
//              // look for circular references
//              if( extend.parent_ids.indexOf( targetExtend.object_id ) >= 0 ){ continue; }
//
//              // find a match in the target extends self selector (the bit before :extend)
//              selectorPath = [targetExtend.selfSelectors[0]];
//              matches = extendVisitor.findMatch(extend, selectorPath);
//
//              if (matches.length) {
//
//                  extend.hasFoundMatches = true;
//
//                  // we found a match, so for each self selector..
//                  extend.selfSelectors.forEach(function(selfSelector) {
//
//                      // process the extend as usual
//                      newSelector = extendVisitor.extendSelector(matches, selectorPath, selfSelector);
//
//                      // but now we create a new extend from it
//                      newExtend = new(tree.Extend)(targetExtend.selector, targetExtend.option, 0);
//                      newExtend.selfSelectors = newSelector;
//
//                      // add the extend onto the list of extends for that selector
//                      newSelector[newSelector.length - 1].extendList = [newExtend];
//
//                      // record that we need to add it.
//                      extendsToAdd.push(newExtend);
//                      newExtend.ruleset = targetExtend.ruleset;
//
//                      //remember its parents for circular references
//                      newExtend.parent_ids = newExtend.parent_ids.concat(targetExtend.parent_ids, extend.parent_ids);
//
//                      // only process the selector once.. if we have :extend(.a,.b) then multiple
//                      // extends will look at the same selector path, so when extending
//                      // we know that any others will be duplicates in terms of what is added to the css
//                      if (targetExtend.firstExtendOnThisSelectorPath) {
//                          newExtend.firstExtendOnThisSelectorPath = true;
//                          targetExtend.ruleset.paths.push(newSelector);
//                      }
//                  });
//              }
//          }
//      }
//
//      if (extendsToAdd.length) {
//          // try to detect circular references to stop a stack overflow.
//          // may no longer be needed.
//          this.extendChainCount++;
//          if (iterationCount > 100) {
//              var selectorOne = "{unable to calculate}";
//              var selectorTwo = "{unable to calculate}";
//              try
//              {
//                  selectorOne = extendsToAdd[0].selfSelectors[0].toCSS();
//                  selectorTwo = extendsToAdd[0].selector.toCSS();
//              }
//              catch(e) {}
//              throw { message: "extend circular reference detected. One of the circular extends is currently:" +
//                  selectorOne + ":extend(" + selectorTwo + ")"};
//          }
//
//          // now process the new extends on the existing rules so that we can handle a extending b extending c extending
//          // d extending e...
//          return extendsToAdd.concat(extendVisitor.doExtendChaining(extendsToAdd, extendsListTarget, iterationCount + 1));
//      } else {
//          return extendsToAdd;
//      }
//  },
  }

  ///
  void visitRule(Rule ruleNode, VisitArgs visitArgs) {
    visitArgs.visitDeeper = false;

//2.3.1
//  visitRule: function (ruleNode, visitArgs) {
//      visitArgs.visitDeeper = false;
//  },
  }

  ///
  void visitMixinDefinition(MixinDefinition mixinDefinitionNode, VisitArgs visitArgs) {
    visitArgs.visitDeeper = false;

//2.3.1
//  visitMixinDefinition: function (mixinDefinitionNode, visitArgs) {
//      visitArgs.visitDeeper = false;
//  },
  }

  ///
  void visitSelector(Selector selectorNode, VisitArgs visitArgs) {
    visitArgs.visitDeeper = false;

//2.3.1
//  visitSelector: function (selectorNode, visitArgs) {
//      visitArgs.visitDeeper = false;
//  },
  }

  ///
  void visitRuleset(Ruleset rulesetNode, VisitArgs visitArgs) {
    if (rulesetNode.root) return;

    List<Extend>          allExtends = allExtendsStack.last;
    ProcessExtendsVisitor extendVisitor = this;
    List<MatchSelector>   matches;
    List<Selector>        selectorPath;
    List<List<Selector>>  selectorsToAdd = [];

    // look at each selector path in the ruleset, find any extend matches and then copy, find and replace
    for (int extendIndex = 0; extendIndex < allExtends.length; extendIndex++) {
      for(int pathIndex = 0; pathIndex < rulesetNode.paths.length; pathIndex++) {
        selectorPath = rulesetNode.paths[pathIndex];

        // extending extends happens initially, before the main pass
        if (rulesetNode.extendOnEveryPath) continue;
        List<Extend> extendList = selectorPath.last.extendList;
        if (extendList != null && extendList.isNotEmpty) continue;

        matches = findMatch(allExtends[extendIndex], selectorPath);

        if (matches.isNotEmpty) {
          allExtends[extendIndex].hasFoundMatches = true;

          allExtends[extendIndex].selfSelectors.forEach((selfSelector) {
            selectorsToAdd.add(extendVisitor.extendSelector(matches, selectorPath, selfSelector));
          });
        }
      }
    }
    rulesetNode.paths.addAll(selectorsToAdd);

//2.3.1
//  visitRuleset: function (rulesetNode, visitArgs) {
//      if (rulesetNode.root) {
//          return;
//      }
//      var matches, pathIndex, extendIndex, allExtends = this.allExtendsStack[this.allExtendsStack.length - 1],
//          selectorsToAdd = [], extendVisitor = this, selectorPath;
//
//      // look at each selector path in the ruleset, find any extend matches and then copy, find and replace
//
//      for(extendIndex = 0; extendIndex < allExtends.length; extendIndex++) {
//          for(pathIndex = 0; pathIndex < rulesetNode.paths.length; pathIndex++) {
//              selectorPath = rulesetNode.paths[pathIndex];
//
//              // extending extends happens initially, before the main pass
//              if (rulesetNode.extendOnEveryPath) { continue; }
//              var extendList = selectorPath[selectorPath.length - 1].extendList;
//              if (extendList && extendList.length) { continue; }
//
//              matches = this.findMatch(allExtends[extendIndex], selectorPath);
//
//              if (matches.length) {
//                  allExtends[extendIndex].hasFoundMatches = true; **
//
//                  allExtends[extendIndex].selfSelectors.forEach(function(selfSelector) {
//                      selectorsToAdd.push(extendVisitor.extendSelector(matches, selectorPath, selfSelector));
//                  });
//              }
//          }
//      }
//      rulesetNode.paths = rulesetNode.paths.concat(selectorsToAdd);
//  },
  }

  ///
  /// Look through the haystack selector path to try and find the needle - extend.selector
  ///
  /// Returns an array of selector matches that can then be replaced
  ///
  List<MatchSelector> findMatch(Extend extend, List<Selector> haystackSelectorPath) {
    int haystackSelectorIndex; // haystackSelectorPath iteration
    Selector hackstackSelector;
    int hackstackElementIndex;
    Element haystackElement;
    String targetCombinator;
    int i;
    ProcessExtendsVisitor extendVisitor = this;
    List<Element> needleElements = extend.selector.elements;
    List<MatchSelector> potentialMatches = [];
    MatchSelector potentialMatch;
    List<MatchSelector> matches = [];

    // loop through the haystack elements
    for(haystackSelectorIndex = 0; haystackSelectorIndex < haystackSelectorPath.length; haystackSelectorIndex++) {
      hackstackSelector = haystackSelectorPath[haystackSelectorIndex];

      for(hackstackElementIndex = 0; hackstackElementIndex < hackstackSelector.elements.length; hackstackElementIndex++) {
        haystackElement = hackstackSelector.elements[hackstackElementIndex];

        // if we allow elements before our match we can add a potential match every time. otherwise only at the first element.
        if (extend.allowBefore || (haystackSelectorIndex == 0 && hackstackElementIndex == 0)) {
          potentialMatches.add( new MatchSelector()
            ..pathIndex = haystackSelectorIndex
            ..index = hackstackElementIndex
            ..matched = 0
            ..initialCombinator = haystackElement.combinator);
        }

        for (i = 0; i < potentialMatches.length; i++) {
          potentialMatch = potentialMatches[i];

          // selectors add " " onto the first element. When we use & it joins the selectors together, but if we don't
          // then each selector in haystackSelectorPath has a space before it added in the toCSS phase. so we need to work out
          // what the resulting combinator will be
          targetCombinator = haystackElement.combinator.value;
          if (targetCombinator == '' && hackstackElementIndex == 0) {
            targetCombinator = ' ';
          }

          // if we don't match, null our match to indicate failure
          if (!extendVisitor.isElementValuesEqual(needleElements[potentialMatch.matched].value, haystackElement.value) ||
              (potentialMatch.matched > 0 && needleElements[potentialMatch.matched].combinator.value != targetCombinator)) {
            potentialMatch = null;
          } else {
            potentialMatch.matched++;
          }

          // if we are still valid and have finished, test whether we have elements after and whether these are allowed
          if (potentialMatch != null) {
            potentialMatch.finished = (potentialMatch.matched == needleElements.length);
            if (potentialMatch.finished &&
                (!extend.allowAfter && (hackstackElementIndex+1 < hackstackSelector.elements.length || haystackSelectorIndex+1 < haystackSelectorPath.length))) {
              potentialMatch = null;
            }
          }
          // if null we remove, if not, we are still valid, so either push as a valid match or continue
          if (potentialMatch != null) {
            if (potentialMatch.finished) {
              potentialMatch.length = needleElements.length;
              potentialMatch.endPathIndex = haystackSelectorIndex;
              potentialMatch.endPathElementIndex = hackstackElementIndex + 1; // index after end of match
              potentialMatches.length = 0; // we don't allow matches to overlap, so start matching again
              matches.add(potentialMatch);
            }
          } else {
            potentialMatches.removeAt(i);
            i--;
          }
        }
      }
    }
    return matches;

//2.3.1
//  findMatch: function (extend, haystackSelectorPath) {
//      //
//      // look through the haystack selector path to try and find the needle - extend.selector
//      // returns an array of selector matches that can then be replaced
//      //
//      var haystackSelectorIndex, hackstackSelector, hackstackElementIndex, haystackElement,
//          targetCombinator, i,
//          extendVisitor = this,
//          needleElements = extend.selector.elements,
//          potentialMatches = [], potentialMatch, matches = [];
//
//      // loop through the haystack elements
//      for(haystackSelectorIndex = 0; haystackSelectorIndex < haystackSelectorPath.length; haystackSelectorIndex++) {
//          hackstackSelector = haystackSelectorPath[haystackSelectorIndex];
//
//          for(hackstackElementIndex = 0; hackstackElementIndex < hackstackSelector.elements.length; hackstackElementIndex++) {
//
//              haystackElement = hackstackSelector.elements[hackstackElementIndex];
//
//              // if we allow elements before our match we can add a potential match every time. otherwise only at the first element.
//              if (extend.allowBefore || (haystackSelectorIndex === 0 && hackstackElementIndex === 0)) {
//                  potentialMatches.push({pathIndex: haystackSelectorIndex, index: hackstackElementIndex, matched: 0,
//                      initialCombinator: haystackElement.combinator});
//              }
//
//              for(i = 0; i < potentialMatches.length; i++) {
//                  potentialMatch = potentialMatches[i];
//
//                  // selectors add " " onto the first element. When we use & it joins the selectors together, but if we don't
//                  // then each selector in haystackSelectorPath has a space before it added in the toCSS phase. so we need to
//                  // work out what the resulting combinator will be
//                  targetCombinator = haystackElement.combinator.value;
//                  if (targetCombinator === '' && hackstackElementIndex === 0) {
//                      targetCombinator = ' ';
//                  }
//
//                  // if we don't match, null our match to indicate failure
//                  if (!extendVisitor.isElementValuesEqual(needleElements[potentialMatch.matched].value, haystackElement.value) ||
//                      (potentialMatch.matched > 0 && needleElements[potentialMatch.matched].combinator.value !== targetCombinator)) {
//                      potentialMatch = null;
//                  } else {
//                      potentialMatch.matched++;
//                  }
//
//                  // if we are still valid and have finished, test whether we have elements after and whether these are allowed
//                  if (potentialMatch) {
//                      potentialMatch.finished = potentialMatch.matched === needleElements.length;
//                      if (potentialMatch.finished &&
//                          (!extend.allowAfter &&
//                              (hackstackElementIndex + 1 < hackstackSelector.elements.length || haystackSelectorIndex + 1 < haystackSelectorPath.length))) {
//                          potentialMatch = null;
//                      }
//                  }
//                  // if null we remove, if not, we are still valid, so either push as a valid match or continue
//                  if (potentialMatch) {
//                      if (potentialMatch.finished) {
//                          potentialMatch.length = needleElements.length;
//                          potentialMatch.endPathIndex = haystackSelectorIndex;
//                          potentialMatch.endPathElementIndex = hackstackElementIndex + 1; // index after end of match
//                          potentialMatches.length = 0; // we don't allow matches to overlap, so start matching again
//                          matches.push(potentialMatch);
//                      }
//                  } else {
//                      potentialMatches.splice(i, 1);
//                      i--;
//                  }
//              }
//          }
//      }
//      return matches;
//  },
  }

  ///
  /// Compares two elements
  ///
  /// The elements could be String or Node
  ///
  bool isElementValuesEqual(elementValue1, elementValue2) {
    if (elementValue1 is String || elementValue2 is String) {
      return elementValue1 == elementValue2;
    }
    if (elementValue1 is Attribute) {
      if (elementValue1.op != elementValue2.op
          || elementValue1.key != elementValue2.key) {
        return false;
      }
      if (elementValue1.value == null || elementValue2.value ==  null) {
        if (elementValue1.value != null || elementValue2.value != null) {
          return false;
        }
        return true;
      }
      elementValue1 = (elementValue1.value is Node) ? elementValue1.value.value : elementValue1.value;
      elementValue2 = (elementValue2.value is Node) ? elementValue2.value.value : elementValue2.value;
      return elementValue1 == elementValue2;
    }
    elementValue1 = elementValue1.value;
    elementValue2 = elementValue2.value;
    if (elementValue1 is Selector) {
      if (elementValue2 is! Selector
          || elementValue1.elements.length != elementValue2.elements.length) {
        return false;
      }
      for (int i = 0; i < elementValue1.elements.length; i++) {
        if (elementValue1.elements[i].combinator.value != elementValue2.elements[i].combinator.value) {
          if (i != 0
              || getValueOrDefault(elementValue1.elements[i].combinator.value, ' ')
                  != getValueOrDefault(elementValue2.elements[i].combinator.value, ' ')) {
            return false;
          }
        }
        if (!isElementValuesEqual(elementValue1.elements[i].value, elementValue2.elements[i].value)) {
          return false;
        }
      }
      return true;
    }
    return false;

//2.3.1
//  isElementValuesEqual: function(elementValue1, elementValue2) {
//      if (typeof elementValue1 === "string" || typeof elementValue2 === "string") {
//          return elementValue1 === elementValue2;
//      }
//      if (elementValue1 instanceof tree.Attribute) {
//          if (elementValue1.op !== elementValue2.op || elementValue1.key !== elementValue2.key) {
//              return false;
//          }
//          if (!elementValue1.value || !elementValue2.value) {
//              if (elementValue1.value || elementValue2.value) {
//                  return false;
//              }
//              return true;
//          }
//          elementValue1 = elementValue1.value.value || elementValue1.value;
//          elementValue2 = elementValue2.value.value || elementValue2.value;
//          return elementValue1 === elementValue2;
//      }
//      elementValue1 = elementValue1.value;
//      elementValue2 = elementValue2.value;
//      if (elementValue1 instanceof tree.Selector) {
//          if (!(elementValue2 instanceof tree.Selector) || elementValue1.elements.length !== elementValue2.elements.length) {
//              return false;
//          }
//          for(var i = 0; i  < elementValue1.elements.length; i++) {
//              if (elementValue1.elements[i].combinator.value !== elementValue2.elements[i].combinator.value) {
//                  if (i !== 0 || (elementValue1.elements[i].combinator.value || ' ') !== (elementValue2.elements[i].combinator.value || ' ')) {
//                      return false;
//                  }
//              }
//              if (!this.isElementValuesEqual(elementValue1.elements[i].value, elementValue2.elements[i].value)) {
//                  return false;
//              }
//          }
//          return true;
//      }
//      return false;
//  },
  }

  ///
  /// For a set of matches, replace each match with the replacement selector
  ///
  List<Selector> extendSelector (List<MatchSelector> matches, List<Selector> selectorPath, Selector replacementSelector) {
    int currentSelectorPathIndex = 0;
    int currentSelectorPathElementIndex = 0;
    List<Selector> path = [];
    int matchIndex;
    Selector selector;
    Element firstElement;
    MatchSelector match;
    List<Element> newElements;

    for (matchIndex = 0; matchIndex < matches.length; matchIndex++) {
      match = matches[matchIndex];
      selector = selectorPath[match.pathIndex];
      firstElement = new Element(
        match.initialCombinator,
        replacementSelector.elements[0].value,
        replacementSelector.elements[0].index,
        replacementSelector.elements[0].currentFileInfo
      );

      if (match.pathIndex > currentSelectorPathIndex && currentSelectorPathElementIndex > 0) {
        path.last.elements.addAll(selectorPath[currentSelectorPathIndex].elements.sublist(currentSelectorPathElementIndex));
        currentSelectorPathElementIndex = 0;
        currentSelectorPathIndex++;
      }

      newElements = selector.elements.sublist(currentSelectorPathElementIndex, match.index)
          ..add(firstElement)
          ..addAll(replacementSelector.elements.sublist(1));

      if (currentSelectorPathIndex == match.pathIndex && matchIndex > 0) {
        path.last.elements.addAll(newElements);
      } else {
        path.addAll(selectorPath.sublist(currentSelectorPathIndex, match.pathIndex));
        path.add(new Selector(newElements));
      }
      currentSelectorPathIndex = match.endPathIndex;
      currentSelectorPathElementIndex = match.endPathElementIndex;
      if (currentSelectorPathElementIndex >= selectorPath[currentSelectorPathIndex].elements.length) {
        currentSelectorPathElementIndex = 0;
        currentSelectorPathIndex++;
      }
    }

    if (currentSelectorPathIndex < selectorPath.length && currentSelectorPathElementIndex > 0) {
      path.last.elements.addAll(selectorPath[currentSelectorPathIndex].elements.sublist(currentSelectorPathElementIndex));
      currentSelectorPathIndex++;
    }
    path.addAll(selectorPath.sublist(currentSelectorPathIndex, selectorPath.length));
    return path;

//2.3.1
//  extendSelector:function (matches, selectorPath, replacementSelector) {
//
//      //for a set of matches, replace each match with the replacement selector
//
//      var currentSelectorPathIndex = 0,
//          currentSelectorPathElementIndex = 0,
//          path = [],
//          matchIndex,
//          selector,
//          firstElement,
//          match,
//          newElements;
//
//      for (matchIndex = 0; matchIndex < matches.length; matchIndex++) {
//          match = matches[matchIndex];
//          selector = selectorPath[match.pathIndex];
//          firstElement = new tree.Element(
//              match.initialCombinator,
//              replacementSelector.elements[0].value,
//              replacementSelector.elements[0].index,
//              replacementSelector.elements[0].currentFileInfo
//          );
//
//          if (match.pathIndex > currentSelectorPathIndex && currentSelectorPathElementIndex > 0) {
//              path[path.length - 1].elements = path[path.length - 1]
//                  .elements.concat(selectorPath[currentSelectorPathIndex].elements.slice(currentSelectorPathElementIndex));
//              currentSelectorPathElementIndex = 0;
//              currentSelectorPathIndex++;
//          }
//
//          newElements = selector.elements
//              .slice(currentSelectorPathElementIndex, match.index)
//              .concat([firstElement])
//              .concat(replacementSelector.elements.slice(1));
//
//          if (currentSelectorPathIndex === match.pathIndex && matchIndex > 0) {
//              path[path.length - 1].elements =
//                  path[path.length - 1].elements.concat(newElements);
//          } else {
//              path = path.concat(selectorPath.slice(currentSelectorPathIndex, match.pathIndex));
//
//              path.push(new tree.Selector(
//                  newElements
//              ));
//          }
//          currentSelectorPathIndex = match.endPathIndex;
//          currentSelectorPathElementIndex = match.endPathElementIndex;
//          if (currentSelectorPathElementIndex >= selectorPath[currentSelectorPathIndex].elements.length) {
//              currentSelectorPathElementIndex = 0;
//              currentSelectorPathIndex++;
//          }
//      }
//
//      if (currentSelectorPathIndex < selectorPath.length && currentSelectorPathElementIndex > 0) {
//          path[path.length - 1].elements = path[path.length - 1]
//              .elements.concat(selectorPath[currentSelectorPathIndex].elements.slice(currentSelectorPathElementIndex));
//          currentSelectorPathIndex++;
//      }
//
//      path = path.concat(selectorPath.slice(currentSelectorPathIndex, selectorPath.length));
//
//      return path;
//  },
  }

  ///
  void visitRulesetOut (Ruleset rulesetNode) { }

//2.3.1
//  visitRulesetOut: function (rulesetNode) {
//  },

  ///
  void visitMedia (Media mediaNode, VisitArgs visitArgs) {
    List<Extend> newAllExtends = mediaNode.allExtends.sublist(0)..addAll(allExtendsStack.last);
    newAllExtends.addAll(doExtendChaining(newAllExtends, mediaNode.allExtends));
    allExtendsStack.add(newAllExtends);

//2.3.1
//  visitMedia: function (mediaNode, visitArgs) {
//      var newAllExtends = mediaNode.allExtends.concat(this.allExtendsStack[this.allExtendsStack.length - 1]);
//      newAllExtends = newAllExtends.concat(this.doExtendChaining(newAllExtends, mediaNode.allExtends));
//      this.allExtendsStack.push(newAllExtends);
//  },
  }

  ///
  void visitMediaOut (Media mediaNode) {
    allExtendsStack.removeLast();

//2.4.0+4
//  visitMediaOut: function (mediaNode) {
//      var lastIndex = this.allExtendsStack.length - 1;
//      this.allExtendsStack.length = lastIndex;
//  },
  }

  ///
  void visitDirective (Directive directiveNode, VisitArgs visitArgs) {
    List<Extend> newAllExtends =  directiveNode.allExtends.sublist(0)..addAll(allExtendsStack.last);
    newAllExtends.addAll(doExtendChaining(newAllExtends, directiveNode.allExtends));
    allExtendsStack.add(newAllExtends);

//2.3.1
//  visitDirective: function (directiveNode, visitArgs) {
//      var newAllExtends = directiveNode.allExtends.concat(this.allExtendsStack[this.allExtendsStack.length - 1]);
//      newAllExtends = newAllExtends.concat(this.doExtendChaining(newAllExtends, directiveNode.allExtends));
//      this.allExtendsStack.push(newAllExtends);
//  },
  }

  ///
  void visitDirectiveOut (Directive directiveNode) {
    allExtendsStack.removeLast();

//2.4.0+4
//  visitDirectiveOut: function (directiveNode) {
//      var lastIndex = this.allExtendsStack.length - 1;
//      this.allExtendsStack.length = lastIndex;
//  }
  }

  /// func visitor.visit distribuitor
  Function visitFtn(Node node) {
    if (node is Media)      return visitMedia;
    if (node is Directive)  return visitDirective;
    if (node is MixinDefinition) return visitMixinDefinition;
    if (node is Rule)       return visitRule;
    if (node is Ruleset)    return visitRuleset;
    if (node is Selector)   return visitSelector;

    return null;
  }

  /// funcOut visitor.visit distribuitor
  Function visitFtnOut(Node node) {
    if (node is Media)      return visitMediaOut;
    if (node is Directive)  return visitDirectiveOut;
    if (node is Ruleset)    return visitRulesetOut;

    return null;
  }
}

class MatchSelector {
  int   endPathElementIndex;
  int   endPathIndex;
  bool  finished;
  int   index;
  Combinator initialCombinator;
  int   length;
  int   matched;
  int   pathIndex;
}
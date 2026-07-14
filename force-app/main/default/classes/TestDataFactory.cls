@IsTest
@SuppressWarnings(
  'PMD.AvoidDebugStatements, PMD.ApexDoc, PMD.CyclomaticComplexity, PMD.IfStmtsMustUseBraces, PMD.IfElseStmtsMustUseBraces, PMD.DebugsShouldUseLoggingLevel, PMD.EmptyCatchBlock, PMD.ApexAssertionsShouldIncludeMessage, PMD.CognitiveComplexity, PMD.ExcessiveParameterList, PMD.StdCyclomaticComplexity, PMD.AvoidDeeplyNestedIfStmts, PMD.NcssMethodCount, PMD.ApexUnitTestClassShouldHaveAsserts, PMD.FieldDeclarationsShouldBeAtStart, PMD.ForLoopsMustUseBraces, PMD.UnusedLocalVariable, PMD.ExcessivePublicCount, PMD.NcssTypeCount, PMD.ApexSuggestUsingNamedCred, PMD.AvoidHardcodingId, PMD.ApexSOQLInjection'
)
public class TestDataFactory {
  public static User createAdminUser() {
    Profile p = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    String randomStr =
      String.valueOf(DateTime.now().getTime()) +
      String.valueOf(Crypto.getRandomInteger());
    User u = new User(
      Alias = 'standt',
      Email = 'adminuser' + randomStr + '@testorg.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Testing',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = 'adminuser' + randomStr + '@testorg.com'
    );
    insert u;
    return u;
  }
}
